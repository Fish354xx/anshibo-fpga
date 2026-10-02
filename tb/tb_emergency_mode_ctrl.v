// ============================================================================
// emergency_mode_ctrl 自检 TestBench
// - 使用缩短参数仿真（CLK_FREQ_HZ=20000, DEBOUNCE_MS=1）
// - 覆盖需求 R1~R9（普通轮播、应急进入/退出、长按消抖、加载冲突抑制等）
// - 追加 T10/T11：恢复未完成时再次进入应急（恢复索引不得被污染为 3）、
//   快速连续切换与"按键脉冲/加载完成同周期"的偏移扫描
// - Verilog-2001 + iverilog 可编译
// ============================================================================
`timescale 1ns / 1ps

module tb_emergency_mode_ctrl;

    // -----------------------------------------------------------------------
    // 缩短参数：消抖 DEB_CYCLES = (20000/1000)*1 = 20 拍
    //           自动轮播 AUTO_PERIOD = 20000 拍
    // -----------------------------------------------------------------------
    localparam integer CLK_FREQ_HZ = 20000;
    localparam integer DEBOUNCE_MS = 1;
    localparam integer DEB_CYCLES  = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS; // 20
    localparam integer AUTO_PERIOD = CLK_FREQ_HZ;                         // 20000

    // -----------------------------------------------------------------------
    // 时钟
    // -----------------------------------------------------------------------
    reg clk;
    initial clk = 1'b0;
    always #10 clk = ~clk; // 50MHz 仿真时钟

    // -----------------------------------------------------------------------
    // DUT 信号
    // -----------------------------------------------------------------------
    reg         rst;
    reg         key_mode;
    reg         key_next_press;
    reg         key_auto_press;
    reg         pause_rotate=1'b0;
    reg         scan_done;
    reg         bmp_ready;
    reg  [2:0]  img_found_count;
    reg  [1:0]  m_img_idx;

    wire        emergency_mode;
    wire        load_req;
    wire [1:0]  load_req_idx;
    wire        load_req_is_emergency;
    wire        disp_commit_en;

    // 父模块模型信号
    reg         m_load_busy;
    reg         m_display_valid;
    reg         m_first_committed;
    reg  [1:0]  m_load_idx;
    reg         m_load_is_emerg;
    reg         m_disp_buf;          // 0 或 1，表示当前显示缓冲区编号
    reg  [1:0]  m_pending_buf;       // 加载时记住的缓冲切换目标
    integer     m_load_timer;
    integer     load_hold;           // 加载事务持续拍数（可调）

    // 统计
    integer     commit_cnt;
    integer     supp_cnt;
    integer     supp_kept;
    integer     bad_emerg_commit;
    integer     bad_normal_commit;

    // 模式跳变监测
    reg         prev_emergency_mode;
    integer     mode_edges;

    // 自检统计
    integer     pass_cnt;
    integer     fail_cnt;

    // -----------------------------------------------------------------------
    // DUT 例化
    // -----------------------------------------------------------------------
    emergency_mode_ctrl #(
        .CLK_FREQ_HZ          (CLK_FREQ_HZ),
        .DEBOUNCE_MS          (DEBOUNCE_MS),
        .EMERGENCY_INDEX      (2'd3),
        .EMERGENCY_MIN_IMAGES (3'd4),
        .NORMAL_ROTATE_COUNT  (3'd3)
    ) u_dut (
        .clk                  (clk),
        .rst                  (rst),
        .key_mode             (key_mode),
        .key_next_press       (key_next_press),
        .key_auto_press       (key_auto_press),
        .pause_rotate         (pause_rotate),
        .scan_done            (scan_done),
        .bmp_ready            (bmp_ready),
        .first_image_committed(m_first_committed),
        .display_valid        (m_display_valid),
        .load_busy            (m_load_busy),
        .img_found_count      (img_found_count),
        .cur_img_idx          (m_img_idx),
        .emergency_mode       (emergency_mode),
        .load_req             (load_req),
        .load_req_idx         (load_req_idx),
        .load_req_is_emergency(load_req_is_emergency),
        .disp_commit_en       (disp_commit_en)
    );

    // -----------------------------------------------------------------------
    // 父模块行为模型：接受 load_req → 模拟加载 → 根据 disp_commit_en 决定是否切显示
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            m_load_busy       <= 1'b0;
            m_display_valid   <= 1'b0;
            m_first_committed <= 1'b0;
            m_img_idx         <= 2'd0;
            m_load_idx        <= 2'd0;
            m_load_is_emerg   <= 1'b0;
            m_disp_buf        <= 1'b0;
            m_pending_buf     <= 2'd0;
            m_load_timer      <= 0;
        end else begin
            if (m_load_busy) begin
                m_load_timer <= m_load_timer + 1;
                if (m_load_timer >= (load_hold - 1)) begin
                    m_load_busy <= 1'b0;
                    m_load_timer <= 0;
                    if (disp_commit_en) begin
                        m_img_idx         <= m_load_idx;
                        m_disp_buf        <= m_pending_buf[0];
                        m_display_valid   <= 1'b1;
                        m_first_committed <= 1'b1;
                        commit_cnt        <= commit_cnt + 1;
                        // 不变量统计
                        if (emergency_mode && (m_load_idx != 2'd3))
                            bad_emerg_commit <= bad_emerg_commit + 1;
                        if (!emergency_mode && (m_load_idx == 2'd3))
                            bad_normal_commit <= bad_normal_commit + 1;
                    end else begin
                        supp_cnt  <= supp_cnt + 1;
                        supp_kept <= supp_kept + 1;
                    end
                end
            end else begin
                if (load_req && !m_load_busy) begin
                    m_load_busy     <= 1'b1;
                    m_load_idx      <= load_req_idx;
                    m_load_is_emerg <= load_req_is_emergency;
                    m_pending_buf   <= m_display_valid ? {1'b0, ~m_disp_buf} : 2'd0;
                    m_load_timer    <= 0;
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // 模式跳变监测
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_emergency_mode <= 1'b0;
            mode_edges          <= 0;
        end else begin
            prev_emergency_mode <= emergency_mode;
            if (emergency_mode !== prev_emergency_mode)
                mode_edges <= mode_edges + 1;
        end
    end

    // -----------------------------------------------------------------------
    // 全局看门狗
    // -----------------------------------------------------------------------
    initial begin
        #60_000_000;
        $display("[FAIL] global timeout");
        $fatal(1);
    end

    // -----------------------------------------------------------------------
    // Task: check
    // -----------------------------------------------------------------------
    task check;
        input        cond;
        input [8*64-1:0] msg;
        begin
            if (cond) begin
                $display("[PASS] %0s", msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %0s", msg);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: press_mode — 模拟一次完整模式按键按下（低电平 6*DEB_CYCLES 拍）
    // -----------------------------------------------------------------------
    task press_mode;
        integer i;
        begin
            key_mode <= 1'b0;
            for (i = 0; i < 6 * DEB_CYCLES; i = i + 1)
                @(posedge clk);
            key_mode <= 1'b1;
            // 等待消抖稳定 + 额外几拍让 DUT 响应
            for (i = 0; i < 4 * DEB_CYCLES; i = i + 1)
                @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: press_mode_long — 长按模式键（低电平 20*DEB_CYCLES 拍）
    // -----------------------------------------------------------------------
    task press_mode_long;
        integer i;
        begin
            key_mode <= 1'b0;
            for (i = 0; i < 20 * DEB_CYCLES; i = i + 1)
                @(posedge clk);
            key_mode <= 1'b1;
            for (i = 0; i < 4 * DEB_CYCLES; i = i + 1)
                @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: pulse_next — 手动下一张单周期脉冲
    // -----------------------------------------------------------------------
    task pulse_next;
        begin
            key_next_press <= 1'b1;
            @(posedge clk);
            key_next_press <= 1'b0;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: pulse_auto — 自动轮播开关单周期脉冲
    // -----------------------------------------------------------------------
    task pulse_auto;
        begin
            key_auto_press <= 1'b1;
            @(posedge clk);
            key_auto_press <= 1'b0;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: wait_idle — 等 load_busy 变 0 再等 4 拍，带超时保护
    // -----------------------------------------------------------------------
    task wait_idle;
        integer timeout;
        begin
            timeout = 0;
            // 等按键挂起请求被父模块接受，避免忙信号尚未拉高就返回。
            repeat (4) @(posedge clk);
            #1;
            while (m_load_busy && timeout < 10000) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            repeat (4) @(posedge clk);
            #1;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: wait_cycles — 等待 N 个时钟周期
    // -----------------------------------------------------------------------
    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: wait_idx — 轮询等待显示索引变为 target，带超时保护
    // -----------------------------------------------------------------------
    task wait_idx;
        input [1:0] target;
        integer timeout;
        begin
            timeout = 0;
            while ((m_img_idx !== target) && (timeout < 40000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            repeat (4) @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: goto_idx — 通过手动切图走到指定普通图索引（最多 3 次）
    // -----------------------------------------------------------------------
    task goto_idx;
        input [1:0] target;
        integer guard;
        begin
            guard = 0;
            while ((m_img_idx !== target) && (guard < 8)) begin
                pulse_next;
                wait_idle;
                guard = guard + 1;
            end
            repeat (4) @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // 初始化
    // -----------------------------------------------------------------------
    initial begin
        rst               = 1'b1;
        key_mode          = 1'b1;  // 松开
        key_next_press    = 1'b0;
        key_auto_press    = 1'b0;
        scan_done         = 1'b0;
        bmp_ready         = 1'b1;
        img_found_count   = 3'd4;
        load_hold         = 200;

        // 统计清零
        commit_cnt        = 0;
        supp_cnt          = 0;
        supp_kept         = 0;
        bad_emerg_commit  = 0;
        bad_normal_commit = 0;
        pass_cnt          = 0;
        fail_cnt          = 0;

        $display("========================================");
        $display("  TB: emergency_mode_ctrl self-check");
        $display("========================================");
    end

    // -----------------------------------------------------------------------
    // 主测试流程
    // -----------------------------------------------------------------------
    initial begin : main_test
        integer pre_idx;
        integer pre_commit;
        integer pre_supp;
        integer pre_supp_kept;
        integer pre_mode_edges;
        integer i;
        reg [1:0] auto_pre_idx;

        // ================================================================
        // 复位
        // ================================================================
        repeat (20) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        // ================================================================
        // T0: 复位后 emergency_mode==0（R8），首图提交前 display_valid==0
        // ================================================================
        $display("\n--- T0: Reset smoke ---");
        check(emergency_mode == 1'b0, "T0: emergency_mode==0 after reset");
        check(m_display_valid == 1'b0, "T0: display_valid==0 before first commit");

        // ================================================================
        // T1: scan_done=1 后首图自动加载
        // ================================================================
        $display("\n--- T1: First image auto-load ---");
        scan_done = 1'b1;
        repeat (8) @(posedge clk);   // 等加载真正启动（load_busy 需要 1 拍才被父模块拉高）再 wait_idle
        wait_idle;
        check(m_display_valid == 1'b1, "T1: display_valid==1 after first load");
        check(m_img_idx == 2'd0, "T1: img_idx==0 after first load");
        check(m_first_committed == 1'b1, "T1: first_image_committed==1");

        // ================================================================
        // T2: 连续 3 次 pulse_next 得到 1、2、0（索引 3 不参与普通轮播，R1）
        // ================================================================
        $display("\n--- T2: Normal rotation 0->1->2->0 ---");
        // 当前 m_img_idx==0，切到 1
        pulse_next;
        wait_idle;
        check(m_img_idx == 2'd1, "T2: next from 0 -> 1");

        // 切到 2
        pulse_next;
        wait_idle;
        check(m_img_idx == 2'd2, "T2: next from 1 -> 2");

        // 切到 0（回绕）
        pulse_next;
        wait_idle;
        check(m_img_idx == 2'd0, "T2: next from 2 -> 0 (wrap)");

        // ================================================================
        // T3: img_found_count=3 时 press_mode 被拒绝（R9）
        // ================================================================
        $display("\n--- T3: Reject emergency when img_found_count<4 ---");
        img_found_count = 3'd3;
        pre_commit = commit_cnt;
        press_mode;
        wait_idle;
        check(emergency_mode == 1'b0, "T3: emergency_mode still 0 (rejected)");
        check(m_img_idx == 2'd0, "T3: img_idx unchanged");
        check(commit_cnt == pre_commit, "T3: no new commit");
        img_found_count = 3'd4; // 恢复

        // ================================================================
        // T4: 切到索引 1 后进入应急（R2/R3）
        // ================================================================
        $display("\n--- T4: Enter emergency mode ---");
        pulse_next;
        wait_idle;
        check(m_img_idx == 2'd1, "T4: moved to idx 1 before emergency");
        pre_idx = m_img_idx; // pre_idx = 1

        press_mode;
        wait_idle;
        check(emergency_mode == 1'b1, "T4: emergency_mode==1");
        check(m_img_idx == 2'd3, "T4: img_idx==3 (emergency image)");
        check(m_display_valid == 1'b1, "T4: display_valid still 1");

        // ================================================================
        // T5: 应急模式下 pulse_next/pulse_auto 无效（R6）
        // ================================================================
        $display("\n--- T5: Keys ignored in emergency mode ---");
        pre_commit = commit_cnt;
        pre_supp   = supp_cnt;

        pulse_next;
        wait_idle;
        check(m_img_idx == 2'd3, "T5: idx still 3 after pulse_next");

        pulse_auto;
        wait_idle;
        check(m_img_idx == 2'd3, "T5: idx still 3 after pulse_auto");
        check(commit_cnt == pre_commit, "T5: no new commit in emergency");
        check(supp_cnt == pre_supp, "T5: no suppressed load in emergency");

        // ================================================================
        // T6: 退出应急恢复到进入前的普通图（R7）
        // ================================================================
        $display("\n--- T6: Exit emergency, restore previous image ---");
        press_mode;
        wait_idle;
        check(emergency_mode == 1'b0, "T6: emergency_mode==0");
        check(m_img_idx == pre_idx[1:0], "T6: img_idx restored to pre_idx");

        // ================================================================
        // T7: 自动轮播联动（应急期间不推进，退出后继续，R6 扩展）
        // ================================================================
        $display("\n--- T7: Auto-play interaction with emergency ---");

        // 先确保在索引 0 上
        // 当前 m_img_idx 为 pre_idx（=1），先切到 0
        pulse_next;
        wait_idle;
        // 可能到了 2 或 0，不管具体值，记住当前

        pulse_auto; // 打开自动轮播
        repeat (4) @(posedge clk);

        // 等待 2*AUTO_PERIOD，看索引是否推进
        auto_pre_idx = m_img_idx;
        wait_cycles(2 * AUTO_PERIOD);
        check(m_img_idx !== auto_pre_idx, "T7: auto-play advances index");

        // 记住进入应急前的索引
        auto_pre_idx = m_img_idx;
        pre_idx = m_img_idx;

        // 进入应急
        press_mode;
        wait_idle;
        check(emergency_mode == 1'b1, "T7: entered emergency");
        check(m_img_idx == 2'd3, "T7: emergency image loaded");

        // 应急期间按 auto（应被忽略）
        pulse_auto;
        // 再等 2*AUTO_PERIOD，索引应保持 3
        wait_cycles(2 * AUTO_PERIOD);
        check(m_img_idx == 2'd3, "T7: idx stays 3 during emergency (auto ignored)");

        // 退出应急
        press_mode;
        wait_idle;
        check(emergency_mode == 1'b0, "T7: exited emergency");
        check(m_img_idx == pre_idx[1:0], "T7: restored to pre-emergency idx");

        // 退出后自动轮播应继续推进
        auto_pre_idx = m_img_idx;
        wait_cycles(2 * AUTO_PERIOD);
        check(m_img_idx !== auto_pre_idx, "T7: auto-play resumes after exit");

        // 关闭自动轮播
        pulse_auto;
        repeat (4) @(posedge clk);

        // ================================================================
        // T8: 加载中按模式键（R5）——在飞行的普通图不切显示
        // ================================================================
        $display("\n--- T8: Mode switch during active load ---");
        load_hold = 600; // 拉长加载时间

        // 确保 load_busy 为 0
        wait_idle;

        pre_supp      = supp_cnt;
        pre_supp_kept = supp_kept;

        // 发起一次普通图加载
        pulse_next;
        repeat (4) @(posedge clk);
        check(m_load_busy == 1'b1, "T8: load_busy==1 (loading started)");

        // 在加载进行中按模式键
        press_mode;
        check(emergency_mode == 1'b1, "T8: emergency_mode==1 after press during load");

        // 等待加载完成
        wait_idle;

        // 那次在飞行中的普通图加载完成时 disp_commit_en 必须为 0（不切显示）
        check((supp_cnt - pre_supp) >= 1, "T8: suppressed commit incremented");
        check(supp_kept == supp_cnt, "T8: supp_kept matches supp_cnt (display not switched)");

        // 等应急图也加载完
        wait_idle;
        check(m_img_idx == 2'd3, "T8: emergency image loaded after safe completion");

        load_hold = 200; // 恢复

        // 复位并等首图重新显示
        rst = 1'b1;
        repeat (20) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);
        scan_done = 1'b1;
        repeat (8) @(posedge clk);   // 等加载真正启动（load_busy 需要 1 拍才被父模块拉高）再 wait_idle
        wait_idle;
        check(m_display_valid == 1'b1, "T8: display_valid==1 after reset+reload");
        check(m_img_idx == 2'd0, "T8: img_idx==0 after reset+reload");

        // ================================================================
        // T9: 长按只切换一次（R4）
        // ================================================================
        $display("\n--- T9: Long press only toggles once ---");
        wait_idle;
        pre_mode_edges = mode_edges;

        press_mode_long;
        wait_idle;
        check((mode_edges - pre_mode_edges) == 1, "T9: long press = exactly 1 edge");
        check(emergency_mode == 1'b1, "T9: emergency_mode==1 after long press");

        // 短按退出
        pre_mode_edges = mode_edges;
        press_mode;
        wait_idle;
        check((mode_edges - pre_mode_edges) == 1, "T9: short press exit = exactly 1 edge");
        check(emergency_mode == 1'b0, "T9: emergency_mode==0 after exit");

        // ================================================================
        // T10: 恢复未完成时再次进入应急 —— 恢复索引不得被污染为 3
        //      普通图1 -> 进入应急 -> 退出(恢复中) -> 再次进入应急 -> 再退出 -> 恢复普通图1
        // ================================================================
        $display("\n--- T10: Re-enter during restore keeps valid normal restore index ---");
        wait_idle;
        check(emergency_mode == 1'b0, "T10: start in normal mode");
        check(m_img_idx != 2'd3, "T10: start on a normal image");

        // 确定起点为普通图 1
        goto_idx(2'd1);
        wait_idle;
        check(m_img_idx == 2'd1, "T10: at normal image 1");

        // 需求：拉长模拟加载时间，保证一次完整按键消抖操作能发生在加载事务期间
        load_hold = 600;
        check((6 * DEB_CYCLES + 4 * DEB_CYCLES) < load_hold,
              "T10: load window longer than one full key press");

        // 第一次进入应急
        press_mode;
        check(emergency_mode == 1'b1, "T10: entered emergency (1st)");
        wait_idx(2'd3);
        check(m_img_idx == 2'd3, "T10: emergency image 3 displayed");

        // 退出应急：立即开始把普通图 1 恢复进帧缓存，这笔事务需要 600 拍
        press_mode;
        repeat (4) @(posedge clk);
        check(emergency_mode == 1'b0, "T10: exited emergency (1st)");
        check(m_load_busy == 1'b1, "T10: restore load is in flight");
        check(m_load_idx == 2'd1, "T10: restore targets normal image 1");

        // 恢复尚未完成（画面仍是索引 3）时再次进入应急 —— 修复前的实现会在此把 3 存成恢复索引
        pre_supp = supp_cnt;
        press_mode;
        check(emergency_mode == 1'b1, "T10: re-entered emergency during restore");
        check(m_load_busy == 1'b1, "T10: same restore load still in flight at re-entry");

        // 这笔被抑制的恢复事务安全结束后，应急图重新提交
        wait_idle;
        repeat (4) @(posedge clk);
        wait_idle;
        check(emergency_mode == 1'b1, "T10: still in emergency (2nd)");
        check(m_img_idx == 2'd3, "T10: emergency image 3 displayed again");
        check((supp_cnt - pre_supp) >= 1, "T10: in-flight restore suppressed (boundary reached)");

        // 再次退出：必须恢复到普通图 1，而不是索引 3
        press_mode;
        repeat (4) @(posedge clk);
        check(emergency_mode == 1'b0, "T10: exited emergency (2nd)");
        check(m_load_busy == 1'b1, "T10: 2nd restore load started");
        check(m_load_idx == 2'd1, "T10: 2nd restore targets normal image 1 (not index 3)");
        wait_idle;
        check(m_img_idx == 2'd1, "T10: final display restored to normal image 1");

        // ================================================================
        // T11: 快速连续切换 / 按键脉冲与加载完成同周期（偏移扫描）
        //      扫描模式键落点，使其覆盖"按键脉冲正好落在加载结束那一拍"的边界
        // ================================================================
        $display("\n--- T11: Toggle vs load-completion coincidence sweep ---");
        load_hold = 41;      // 短加载窗口，使按键脉冲有机会与加载结束落在同一周期
        wait_idle;

        for (i = 0; i < 16; i = i + 1) begin
            goto_idx(2'd1);
            wait_idle;

            // 发起一次普通图加载，再让按键落点从第 (8+i) 拍开始逐步滑动
            pulse_next;
            wait_cycles(8 + i);
            key_mode = 1'b0;
            wait_cycles(6 * DEB_CYCLES);
            key_mode = 1'b1;
            wait_cycles(4 * DEB_CYCLES);

            check(emergency_mode == 1'b1, "T11: entered emergency after offset press");
            wait_idx(2'd3);
            check(m_img_idx == 2'd3, "T11: emergency image shown");

            // 退出必须恢复到普通图，绝不能是索引 3
            press_mode;
            wait_idle;
            check(emergency_mode == 1'b0, "T11: exited emergency");
            check(m_img_idx != 2'd3, "T11: restored to a normal image (never index 3)");
        end
        load_hold = 200;
        wait_idle;

        // ================================================================
        // 最终不变量汇总
        // ================================================================
        $display("\n--- T12: adjustment pauses rotation and retains emergency priority ---");
        pulse_auto;
        wait_idle;
        pause_rotate=1'b1;
        pre_commit=commit_cnt;
        pulse_next;
        wait_cycles(2*AUTO_PERIOD);
        check(commit_cnt==pre_commit,"T12: no auto/manual load while adjustment is active");
        pre_idx=m_img_idx;
        press_mode;
        wait_idle;
        check(emergency_mode && m_img_idx==3,"T12: emergency remains available while paused");
        press_mode;
        wait_idle;
        check(!emergency_mode && m_img_idx==pre_idx,"T12: exit restores image while paused");
        pause_rotate=1'b0;
        wait_cycles(AUTO_PERIOD+1000);
        check(m_img_idx!=pre_idx,"T12: automatic rotation resumes after adjustment");
        $display("\n--- Final invariant checks ---");
        check(bad_normal_commit == 0, "FINAL: no normal commit loaded emergency image");
        check(bad_emerg_commit == 0, "FINAL: no emergency commit loaded non-emergency image");

        // ================================================================
        // 测试汇总
        // ================================================================
        $display("\n========================================");
        $display("  TEST SUMMARY: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        $display("  commits=%0d suppressed=%0d kept=%0d", commit_cnt, supp_cnt, supp_kept);
        $display("  mode_edges=%0d bad_emerg=%0d bad_normal=%0d",
                 mode_edges, bad_emerg_commit, bad_normal_commit);
        $display("========================================");

        if (fail_cnt == 0) begin
            $display("SIM RESULT: ALL CHECKS PASSED");
            $finish;
        end else begin
            $display("SIM RESULT: %0d CHECKS FAILED", fail_cnt);
            $fatal(1);
        end
    end

endmodule
