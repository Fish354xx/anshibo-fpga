
module hdmi_audio_tone_i2s_64fs #(
    parameter [31:0] PHASE_INC = 32'd39370534,   // 兼容旧顶层，实际本版内部不用它
    parameter signed [23:0] AMP = 24'sd2000000,
    parameter integer NOTE_HOLD_FRAMES = 12000   // 交替提示音，每个音约0.25秒
)(
    input  wire I_mclk,      // 12.288MHz
    input  wire I_rst,
    input  wire I_enable,    // emergency mode; synchronized into audio clock below
    output reg  O_i2s_BCLK,
    output reg  O_i2s_LRCK,
    output reg  O_i2s_DOUT
);

// 应急提示：880Hz与660Hz交替，相位增量按48kHz采样率计算。
function [31:0] note_inc_lut;
    input [2:0] idx;
    begin
        note_inc_lut = idx[0] ? 32'd59055800 : 32'd78741067; // 660 / 880 Hz at 48 kHz
    end
endfunction

reg  [5:0]  S_bit_cnt;
reg  [63:0] S_shift_reg;
reg  [31:0] S_phase_acc;
reg signed [23:0] S_sample_word;
reg signed [23:0] S_sample_next;
reg  [2:0]  S_note_idx;
reg [15:0]  S_note_frame_cnt;

wire [31:0] W_note_inc = note_inc_lut(S_note_idx);
reg enable_sync0, enable_sync1;
always @(posedge I_mclk or posedge I_rst) begin
    if (I_rst) begin
        enable_sync0 <= 1'b0;
        enable_sync1 <= 1'b0;
    end else begin
        enable_sync0 <= I_enable;
        enable_sync1 <= enable_sync0;
    end
end

always @(posedge I_mclk or posedge I_rst) begin
    if (I_rst) begin
        O_i2s_BCLK      <= 1'b0;
        O_i2s_LRCK      <= 1'b0;
        O_i2s_DOUT      <= 1'b0;
        S_bit_cnt       <= 6'd0;
        S_shift_reg     <= 64'd0;
        S_phase_acc     <= 32'd0;
        S_sample_word   <= 24'sd0;
        S_sample_next   <= 24'sd0;
        S_note_idx      <= 3'd0;
        S_note_frame_cnt<= 16'd0;
    end
    else begin
        // 保持和你现有接收端兼容的 64fs 发送时序
        O_i2s_BCLK <= ~O_i2s_BCLK;

        if (O_i2s_BCLK == 1'b1) begin
            O_i2s_DOUT  <= S_shift_reg[63];
            S_shift_reg <= {S_shift_reg[62:0], 1'b0};

            if (S_bit_cnt == 6'd63) begin
                S_bit_cnt <= 6'd0;

                if (O_i2s_LRCK == 1'b0) begin
                    // 左声道发完，右声道复用同一个样本
                    O_i2s_LRCK  <= 1'b1;
                    S_shift_reg <= enable_sync1 ? {S_sample_word[23:0], 40'd0} : 64'd0;
                end
                else begin
                    // 右声道发完，进入下一帧样本
                    O_i2s_LRCK  <= 1'b0;

                    if (!enable_sync1) begin
                        // Continue transmitting zero samples; clocks and HDMI ACR remain running.
                        S_phase_acc <= 32'd0;
                        S_sample_next <= 24'sd0;
                        S_sample_word <= 24'sd0;
                        S_shift_reg <= 64'd0;
                        S_note_idx <= 3'd0;
                        S_note_frame_cnt <= 16'd0;
                    end else begin
                    S_phase_acc <= S_phase_acc + W_note_inc;
                    if (S_phase_acc[31])
                        S_sample_next <= AMP;
                    else
                        S_sample_next <= -AMP;

                    S_sample_word <= S_sample_next;
                    S_shift_reg   <= {S_sample_next[23:0], 40'd0};

                    if (S_note_frame_cnt == NOTE_HOLD_FRAMES - 1) begin
                        S_note_frame_cnt <= 16'd0;
                        if (S_note_idx == 3'd7)
                            S_note_idx <= 3'd0;
                        else
                            S_note_idx <= S_note_idx + 3'd1;
                    end
                    else begin
                        S_note_frame_cnt <= S_note_frame_cnt + 16'd1;
                    end
                    end
                end
            end
            else begin
                S_bit_cnt <= S_bit_cnt + 6'd1;
            end
        end
    end
end

endmodule
