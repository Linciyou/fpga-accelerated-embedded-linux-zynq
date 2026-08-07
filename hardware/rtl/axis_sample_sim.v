// Synthesizable AXI4-Stream sample source for acquisition-path bring-up.
// It emits repeated 1024-sample frames at the AXI clock rate. The alternating
// Q15 real samples form a Nyquist tone, whose 1024-point FFT peak is bin 1
// when the XFFT output uses bit-reversed order.
module axis_sample_sim #(
    parameter integer FRAME_LENGTH = 1024,
    parameter integer AMPLITUDE = 16
) (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        capture_start,
    output reg  [31:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);
    reg [9:0] sample_index;
    reg capture_active;

    function [31:0] sample_word;
        input [9:0] index;
        reg signed [15:0] value;
        begin
            value = index[0] ? -AMPLITUDE : AMPLITUDE;
            sample_word = {16'h0000, value};
        end
    endfunction

    always @(posedge aclk) begin
        if (!aresetn) begin
            sample_index  <= 10'd0;
            m_axis_tdata  <= sample_word(10'd0);
            m_axis_tlast  <= 1'b0;
            m_axis_tvalid <= 1'b0;
            capture_active <= 1'b0;
        end else if (!capture_start) begin
            sample_index   <= 10'd0;
            m_axis_tdata   <= sample_word(10'd0);
            m_axis_tlast   <= 1'b0;
            m_axis_tvalid  <= 1'b0;
            capture_active <= 1'b0;
        end else if (!capture_active) begin
            capture_active <= 1'b1;
            m_axis_tvalid <= 1'b1;
        end else if (m_axis_tready) begin
            if (sample_index == FRAME_LENGTH - 1) begin
                sample_index <= 10'd0;
                m_axis_tdata <= sample_word(10'd0);
                m_axis_tlast <= 1'b0;
                m_axis_tvalid <= 1'b0;
            end else begin
                sample_index <= sample_index + 1'b1;
                m_axis_tdata <= sample_word(sample_index + 1'b1);
                m_axis_tlast <= (sample_index == FRAME_LENGTH - 2);
            end
        end
    end
endmodule
