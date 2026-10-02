`timescale 1ns/1ps
module tb_emergency_audio;
    reg mclk=0, vclk=0, rst=1, enable=0;
    always #40 mclk=~mclk;
    always #20 vclk=~vclk;
    wire bclk,lrck,dout,valid;
    wire [23:0] left,right;
    integer samples=0, nonzero=0, positive=0, negative=0, errors=0;
    integer quiet_check=0;
    hdmi_audio_tone_i2s_64fs #(.NOTE_HOLD_FRAMES(64)) tone(
        .I_mclk(mclk),.I_rst(rst),.I_enable(enable),
        .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
    I2S_receiver receiver(.I_clk(vclk),.I_rst(rst),
        .I_i2s_BCLK(bclk),.I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
        .O_audio_valid(valid),.O_audio_left_data(left),.O_audio_right_data(right));
    always @(posedge vclk) begin
        #1;
        if (!rst && valid) begin
            samples=samples+1;
            if (left!==24'd0 || right!==24'd0) nonzero=nonzero+1;
            if ($signed(left)>0) positive=positive+1;
            if ($signed(left)<0) negative=negative+1;
            if (quiet_check && (left!==24'd0 || right!==24'd0)) begin
                errors=errors+1;
                $display("FAIL: nonzero received sample in normal mode");
            end
        end
    end
    task cycles;
        input integer n;
        begin repeat(n) @(negedge mclk); end
    endtask
    task check;
        input condition;
        input [511:0] message;
        begin
            if (!condition) begin errors=errors+1; $display("FAIL: %0s",message); end
            else $display("PASS: %0s",message);
        end
    endtask
    integer before_samples,before_nonzero;
    initial begin
        cycles(10); rst=0;
        cycles(4096); quiet_check=1; before_samples=samples;
        cycles(8192);
        check(samples-before_samples>=30,"silent mode retains audio valid cadence");
        quiet_check=0; before_nonzero=nonzero; enable=1;
        cycles(65536);
        check(nonzero-before_nonzero>=200,"emergency produces received stereo audio");
        check(positive>0 && negative>0,"tone contains both positive and negative samples");
        enable=0; cycles(4096); quiet_check=1; before_samples=samples;
        cycles(8192);
        check(samples-before_samples>=30,"exit keeps HDMI audio sample cadence");
        quiet_check=0; before_nonzero=nonzero; enable=1;
        cycles(8192);
        check(nonzero-before_nonzero>=20,"second emergency entry restarts audio");
        rst=1; enable=0; cycles(10); rst=0; cycles(4096); quiet_check=1;
        cycles(8192);
        check(errors==0,"normal mode, exit and reset are silent");
        if(errors) $fatal(1,"Audio regression failed: %0d",errors);
        $display("AUDIO RESULT: ALL CHECKS PASSED; samples=%0d nonzero=%0d",samples,nonzero);
        $finish;
    end
    initial begin #20000000; $fatal(1,"Audio timeout"); end
endmodule
