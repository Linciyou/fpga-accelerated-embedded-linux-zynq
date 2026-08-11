// SPDX-License-Identifier: GPL-2.0-only
#include <linux/bitops.h>
#include <linux/completion.h>
#include <linux/dma-mapping.h>
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/jiffies.h>
#include <linux/kernel.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/uaccess.h>

#include <fft_dma_uapi.h>

#define FFT_SAMPLES             1024u
#define FFT_DMA_BYTES           (FFT_SAMPLES * sizeof(u32))

#define S2MM_DMACR              0x30u
#define S2MM_DMASR              0x34u
#define S2MM_DA                 0x48u
#define S2MM_LENGTH             0x58u

#define DMACR_RUNSTOP           BIT(0)
#define DMACR_RESET             BIT(2)
#define DMACR_IOC_IRQEN         BIT(12)
#define DMACR_ERR_IRQEN         BIT(14)
#define DMASR_IDLE              BIT(1)
#define DMASR_IOC_IRQ           BIT(12)
#define DMASR_ERR_MASK          (BIT(4) | BIT(5) | BIT(6) | BIT(14))

struct fft_dma_dev {
    void __iomem *dma_regs;
    void __iomem *capture_regs;
    int irq;
    struct completion completion;
    struct mutex lock;
    u32 *buffer;
    dma_addr_t buffer_dma;
    struct miscdevice miscdev;
};

static irqreturn_t fft_dma_irq(int irq, void *data)
{
    struct fft_dma_dev *fft = data;
    u32 status = readl(fft->dma_regs + S2MM_DMASR);

    if (!(status & (DMASR_IOC_IRQ | DMASR_ERR_MASK)))
        return IRQ_NONE;

    writel(status, fft->dma_regs + S2MM_DMASR);
    complete(&fft->completion);
    return IRQ_HANDLED;
}

static int fft_dma_run(struct fft_dma_dev *fft, struct fft_dma_result *result)
{
    unsigned long timeout;
    u32 status;
    unsigned int i;
    u64 best_magnitude = 0;

    if (upper_32_bits(fft->buffer_dma))
        return -EOVERFLOW;

    memset(fft->buffer, 0, FFT_DMA_BYTES);
    writel(0, fft->capture_regs);

    writel(DMACR_RESET, fft->dma_regs + S2MM_DMACR);
    for (i = 0; i < 10000; ++i) {
        if (!(readl(fft->dma_regs + S2MM_DMACR) & DMACR_RESET))
            break;
        udelay(1);
    }
    if (i == 10000)
        return -ETIMEDOUT;

    writel(~0u, fft->dma_regs + S2MM_DMASR);
    reinit_completion(&fft->completion);
    writel(DMACR_RUNSTOP | DMACR_IOC_IRQEN | DMACR_ERR_IRQEN,
           fft->dma_regs + S2MM_DMACR);
    writel(lower_32_bits(fft->buffer_dma), fft->dma_regs + S2MM_DA);
    writel(FFT_DMA_BYTES, fft->dma_regs + S2MM_LENGTH);
    writel(1, fft->capture_regs);

    timeout = wait_for_completion_timeout(&fft->completion,
                                          msecs_to_jiffies(1000));
    writel(0, fft->capture_regs);
    status = readl(fft->dma_regs + S2MM_DMASR);

    result->dma_status = status;
    result->bytes_received = readl(fft->dma_regs + S2MM_LENGTH);
    if (!timeout)
        return -ETIMEDOUT;
    if (status & DMASR_ERR_MASK)
        return -EIO;
    if (!(status & (DMASR_IOC_IRQ | DMASR_IDLE)))
        return -EIO;

    for (i = 0; i < FFT_SAMPLES; ++i) {
        s16 real = (s16)(fft->buffer[i] & 0xffffu);
        s16 imag = (s16)(fft->buffer[i] >> 16);
        s64 real64 = real;
        s64 imag64 = imag;
        u64 magnitude = real64 * real64 + imag64 * imag64;

        if (magnitude > best_magnitude) {
            best_magnitude = magnitude;
            result->peak_bin = i;
            result->peak_real = real;
            result->peak_imag = imag;
        }
    }
    result->peak_magnitude_squared = best_magnitude;
    return 0;
}

static long fft_dma_ioctl(struct file *file, unsigned int command,
                          unsigned long argument)
{
    struct miscdevice *misc = file->private_data;
    struct fft_dma_dev *fft = container_of(misc, struct fft_dma_dev, miscdev);
    struct fft_dma_result result = { };
    int ret;

    if (command != FFT_DMA_IOCTL_RUN)
        return -ENOTTY;

    mutex_lock(&fft->lock);
    ret = fft_dma_run(fft, &result);
    mutex_unlock(&fft->lock);
    if (ret)
        return ret;

    if (copy_to_user((void __user *)argument, &result, sizeof(result)))
        return -EFAULT;
    return 0;
}

static const struct file_operations fft_dma_fops = {
    .owner = THIS_MODULE,
    .unlocked_ioctl = fft_dma_ioctl,
#ifdef CONFIG_COMPAT
    .compat_ioctl = fft_dma_ioctl,
#endif
};

static int fft_dma_probe(struct platform_device *pdev)
{
    struct fft_dma_dev *fft;
    int ret;

    fft = devm_kzalloc(&pdev->dev, sizeof(*fft), GFP_KERNEL);
    if (!fft)
        return -ENOMEM;

    ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32));
    if (ret)
        return ret;

    fft->dma_regs = devm_platform_ioremap_resource_byname(pdev, "dma");
    if (IS_ERR(fft->dma_regs))
        return PTR_ERR(fft->dma_regs);
    fft->capture_regs = devm_platform_ioremap_resource_byname(pdev, "capture");
    if (IS_ERR(fft->capture_regs))
        return PTR_ERR(fft->capture_regs);

    fft->irq = platform_get_irq(pdev, 0);
    if (fft->irq < 0)
        return fft->irq;

    init_completion(&fft->completion);
    mutex_init(&fft->lock);
    fft->buffer = dma_alloc_coherent(&pdev->dev, FFT_DMA_BYTES,
                                     &fft->buffer_dma, GFP_KERNEL);
    if (!fft->buffer)
        return -ENOMEM;

    ret = devm_request_irq(&pdev->dev, fft->irq, fft_dma_irq, 0,
                           dev_name(&pdev->dev), fft);
    if (ret)
        goto free_buffer;

    fft->miscdev.minor = MISC_DYNAMIC_MINOR;
    fft->miscdev.name = "fft_dma0";
    fft->miscdev.fops = &fft_dma_fops;
    fft->miscdev.parent = &pdev->dev;
    ret = misc_register(&fft->miscdev);
    if (ret)
        goto free_buffer;

    platform_set_drvdata(pdev, fft);
    dev_info(&pdev->dev, "FFT S2MM driver ready, buffer dma=%pad\n",
             &fft->buffer_dma);
    return 0;

free_buffer:
    dma_free_coherent(&pdev->dev, FFT_DMA_BYTES, fft->buffer, fft->buffer_dma);
    return ret;
}

static void fft_dma_remove(struct platform_device *pdev)
{
    struct fft_dma_dev *fft = platform_get_drvdata(pdev);

    writel(0, fft->capture_regs);
    writel(0, fft->dma_regs + S2MM_DMACR);
    misc_deregister(&fft->miscdev);
    dma_free_coherent(&pdev->dev, FFT_DMA_BYTES, fft->buffer, fft->buffer_dma);
}

static const struct of_device_id fft_dma_of_match[] = {
    { .compatible = "bghjn,zynq7020-fft-dma-1.0" },
    { }
};
MODULE_DEVICE_TABLE(of, fft_dma_of_match);

static struct platform_driver fft_dma_driver = {
    .probe = fft_dma_probe,
    .remove = fft_dma_remove,
    .driver = {
        .name = "zynq7020-fft-dma",
        .of_match_table = fft_dma_of_match,
    },
};
module_platform_driver(fft_dma_driver);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Zynq-7020 FFT AXI DMA S2MM driver");
