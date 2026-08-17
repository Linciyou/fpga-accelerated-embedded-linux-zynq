// SPDX-License-Identifier: GPL-2.0-only
#include <linux/completion.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/fs.h>
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

struct fft_dma_dev {
    void __iomem *capture_regs;
    struct dma_chan *rx_chan;
    struct device *dma_dev;
    struct completion completion;
    struct mutex lock;
    u32 *buffer;
    dma_addr_t buffer_dma;
    struct miscdevice miscdev;
};

static void fft_dma_complete(void *data)
{
    struct fft_dma_dev *fft = data;

    complete(&fft->completion);
}

static int fft_dma_run(struct fft_dma_dev *fft, struct fft_dma_result *result)
{
    struct dma_async_tx_descriptor *desc;
    struct dma_slave_config config = {
        .direction = DMA_DEV_TO_MEM,
        .src_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES,
        .src_maxburst = 1,
    };
    struct dma_tx_state state = { };
    enum dma_status status;
    dma_cookie_t cookie;
    unsigned long timeout;
    unsigned int i;
    u64 best_magnitude = 0;
    int ret;

    memset(fft->buffer, 0, FFT_DMA_FRAME_BYTES);
    writel(0, fft->capture_regs);

    ret = dmaengine_slave_config(fft->rx_chan, &config);
    if (ret) {
        dev_err_ratelimited(fft->miscdev.parent,
                            "DMAengine slave configuration failed: %d\n", ret);
        return ret;
    }

    reinit_completion(&fft->completion);
    desc = dmaengine_prep_slave_single(fft->rx_chan, fft->buffer_dma,
                                       FFT_DMA_FRAME_BYTES, DMA_DEV_TO_MEM,
                                       DMA_PREP_INTERRUPT | DMA_CTRL_ACK);
    if (!desc) {
        dev_err_ratelimited(fft->miscdev.parent,
                            "DMAengine did not prepare an S2MM descriptor\n");
        return -EIO;
    }

    desc->callback = fft_dma_complete;
    desc->callback_param = fft;
    cookie = dmaengine_submit(desc);
    ret = dma_submit_error(cookie);
    if (ret) {
        dev_err_ratelimited(fft->miscdev.parent,
                            "DMAengine descriptor submit failed: %d\n", ret);
        return ret;
    }

    dma_async_issue_pending(fft->rx_chan);
    writel(1, fft->capture_regs);
    timeout = wait_for_completion_timeout(&fft->completion,
                                          msecs_to_jiffies(FFT_DMA_TIMEOUT_MS));
    writel(0, fft->capture_regs);
    if (!timeout) {
        dmaengine_terminate_sync(fft->rx_chan);
        dev_err_ratelimited(fft->miscdev.parent,
                            "S2MM DMAengine request timed out after %u ms\n",
                            FFT_DMA_TIMEOUT_MS);
        return -ETIMEDOUT;
    }

    status = dmaengine_tx_status(fft->rx_chan, cookie, &state);
    if (status != DMA_COMPLETE || state.residue) {
        dmaengine_terminate_sync(fft->rx_chan);
        dev_err_ratelimited(fft->miscdev.parent,
                            "S2MM DMAengine completion failed: status=%d residue=%u\n",
                            status, state.residue);
        return -EIO;
    }

    result->dma_status = FFT_DMA_STATUS_COMPLETE;
    result->bytes_received = FFT_DMA_FRAME_BYTES;
    for (i = 0; i < FFT_DMA_FRAME_SAMPLES; ++i) {
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

    fft->capture_regs = devm_platform_ioremap_resource_byname(pdev, "capture");
    if (IS_ERR(fft->capture_regs))
        return PTR_ERR(fft->capture_regs);

    fft->rx_chan = dma_request_chan(&pdev->dev, "rx");
    if (IS_ERR(fft->rx_chan))
        return dev_err_probe(&pdev->dev, PTR_ERR(fft->rx_chan),
                             "failed to request S2MM DMAengine channel\n");
    fft->dma_dev = dmaengine_get_dma_device(fft->rx_chan);

    init_completion(&fft->completion);
    mutex_init(&fft->lock);
    fft->buffer = dma_alloc_coherent(fft->dma_dev, FFT_DMA_FRAME_BYTES,
                                     &fft->buffer_dma, GFP_KERNEL);
    if (!fft->buffer) {
        ret = -ENOMEM;
        goto release_channel;
    }

    fft->miscdev.minor = MISC_DYNAMIC_MINOR;
    fft->miscdev.name = "fft_dma0";
    fft->miscdev.fops = &fft_dma_fops;
    fft->miscdev.parent = &pdev->dev;
    ret = misc_register(&fft->miscdev);
    if (ret)
        goto free_buffer;

    platform_set_drvdata(pdev, fft);
    dev_info(&pdev->dev, "FFT DMAengine client ready, buffer dma=%pad\n",
             &fft->buffer_dma);
    return 0;

free_buffer:
    dma_free_coherent(fft->dma_dev, FFT_DMA_FRAME_BYTES, fft->buffer,
                      fft->buffer_dma);
release_channel:
    dma_release_channel(fft->rx_chan);
    return ret;
}

static void fft_dma_remove(struct platform_device *pdev)
{
    struct fft_dma_dev *fft = platform_get_drvdata(pdev);

    writel(0, fft->capture_regs);
    dmaengine_terminate_sync(fft->rx_chan);
    misc_deregister(&fft->miscdev);
    dma_free_coherent(fft->dma_dev, FFT_DMA_FRAME_BYTES, fft->buffer,
                      fft->buffer_dma);
    dma_release_channel(fft->rx_chan);
}

static const struct of_device_id fft_dma_of_match[] = {
    { .compatible = "bghjn,zynq7020-fft-dmaengine-2.0" },
    { }
};
MODULE_DEVICE_TABLE(of, fft_dma_of_match);

static struct platform_driver fft_dma_driver = {
    .probe = fft_dma_probe,
    .remove = fft_dma_remove,
    .driver = {
        .name = "zynq7020-fft-dmaengine",
        .of_match_table = fft_dma_of_match,
    },
};
module_platform_driver(fft_dma_driver);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Zynq-7020 FFT DMAengine client driver");
