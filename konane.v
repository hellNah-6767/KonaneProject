module konane (
    input clk,
    input rst_n,

    output reg op_ready,
    input op_valid,
    input signed [4:0] op_i,
    input signed [4:0] op_j,

    input re_ready,
    output reg re_valid,
    output reg re_is_finished,
    output reg re_next_player_id,
    output reg re_player_can_giveup,
    output reg [35:0] re_selectable
);

localparam BLACK = 0, WHITE = 1;// define the identification of player

localparam NORTH = 0,//define the direction into binary number
           EAST  = 1,
           SOUTH = 2,
           WEST  = 3;

localparam S_CH_OP       = 0,//to define the order of executing
           S_CH_RE       = 1,
           S_JCH_OP      = 2,
           S_J_MV        = 3,
           S_J_UPDATE    = 4,
           S_J_JUDGE     = 5,
           S_J_STILL_RE  = 6,
           S_J_NOMOVE_RE = 7,
           S_JN_OP       = 8;


// It can be observed that black cells are restricted to holding only black pieces, and white cells only white pieces.
// We created two bit map:
//     BLACK_POSSIBLE: 6*6 bit map, "if and only if" position i, j is a restricted-to-holding black cell, the BLACK_POSSIBLE[6*i+j] will be 1.
//     WHITE_POSSIBLE: 6*6 bit map, "if and only if" position i, j is a restricted-to-holding white cell, the WHITE_POSSIBLE[6*i+j] will be 1.
localparam BLACK_POSSIBLE = {// to place the black pieces
    3{
        {3{2'b10}}, {3{2'b01}}
    }
};

localparam WHITE_POSSIBLE = {// to place/limit the white pieces
    3{
        {3{2'b01}}, {3{2'b10}}
    }
};

reg op_ready_nxt;//ready for input
reg re_valid_nxt;//validity of output
reg re_is_finished_nxt;// is the game finished
reg re_next_player_id_nxt;//to check who is the next player


reg [3:0] S, S_nxt;

reg player_id, player_id_nxt;
reg [4:0] ci, ci_nxt;//current place
reg [4:0] cj, cj_nxt;
reg [4:0] ji, ji_nxt;//jump place
reg [4:0] jj, jj_nxt;
reg [4:0] ui, ui_nxt;// update place
reg [4:0] uj, uj_nxt;
reg [1:0] dir, dir_nxt;//direction

reg [35:0] occupied /* verilator public */;//occupied block
reg [35:0] occupied_nxt;

reg [35:0] N_canjump, N_canjump_nxt;//avaliable block
reg [35:0] E_canjump, E_canjump_nxt;
reg [35:0] S_canjump, S_canjump_nxt;
reg [35:0] W_canjump, W_canjump_nxt;

reg op_fire, re_fire;

wire [35:0] su_o_update;


reg [35:0] black_all /* verilator public */;
reg [35:0] white_all /* verilator public */;
reg [35:0] black_movable_all;
reg [35:0] white_movable_all;
reg [35:0] N_cij_can_jumpto;//places can jump to 
reg [35:0] E_cij_can_jumpto;
reg [35:0] S_cij_can_jumpto;
reg [35:0] W_cij_can_jumpto;
reg [35:0] all_cij_can_jumpto;
reg black_no_move, white_no_move;

reg [6:0] cij2idx;
reg [6:0] jij2idx;
reg [6:0] uij2idx;
reg [6:0] op_ij2idx;
reg signed [4:0] i_dist, j_dist;

reg [35:0] selectable;

integer i, j;

reg [7:0] step_count, step_count_nxt;
reg [7:0] best_step, best_step_nxt;


always @(*) begin
    op_fire = op_ready & op_valid;
    re_fire = re_ready & re_valid;

    cij2idx = ci * 6 + cj;//change from coordinate to a list No.
    jij2idx = ji * 6 + jj;
    uij2idx = ui * 6 + uj;
    op_ij2idx = op_i * 6 + op_j;

    black_all = BLACK_POSSIBLE & occupied;//avaliable vacency
    white_all = WHITE_POSSIBLE & occupied;
    black_movable_all = black_all & (N_canjump | E_canjump | S_canjump | W_canjump);
    white_movable_all = white_all & (N_canjump | E_canjump | S_canjump | W_canjump);
    for (i = 0; i < 6; i = i + 1) begin//check if i, j can jump cani, canj
        for (j = 0; j < 6; j = j + 1) begin
            N_cij_can_jumpto[i * 6 + j] = ((ci > 1) && ((ci - 2) == i) && (cj == j) && N_canjump[cij2idx]);
            E_cij_can_jumpto[i * 6 + j] = ((cj < 4) && ((cj + 2) == j) && (ci == i) && E_canjump[cij2idx]);
            S_cij_can_jumpto[i * 6 + j] = ((ci < 4) && ((ci + 2) == i) && (cj == j) && S_canjump[cij2idx]);
            W_cij_can_jumpto[i * 6 + j] = ((cj > 1) && ((cj - 2) == j) && (ci == i) && W_canjump[cij2idx]);
        end
    end
    all_cij_can_jumpto = N_cij_can_jumpto | E_cij_can_jumpto | S_cij_can_jumpto | W_cij_can_jumpto;//to produce the block avaliable

    black_no_move = ~|(black_all & (N_canjump | E_canjump | S_canjump | W_canjump));//dead
    white_no_move = ~|(white_all & (N_canjump | E_canjump | S_canjump | W_canjump));//dead

    i_dist = ji - ci;
    j_dist = jj - cj;

    op_ready_nxt = op_ready;
    re_valid_nxt = re_valid;
    step_count_nxt = step_count;
    best_step_nxt = best_step;
    re_is_finished_nxt = re_is_finished;
    re_next_player_id_nxt = re_next_player_id;

    S_nxt = S;

    player_id_nxt = player_id;
    ci_nxt = ci;
    cj_nxt = cj;
    ji_nxt = ji;
    jj_nxt = jj;
    ui_nxt = ui;
    uj_nxt = uj;
    dir_nxt = dir;

    occupied_nxt = occupied;
    N_canjump_nxt = N_canjump;
    E_canjump_nxt = E_canjump;
    S_canjump_nxt = S_canjump;
    W_canjump_nxt = W_canjump;

    case (S)
        S_CH_OP: begin
            if (op_fire) begin
                op_ready_nxt = 0;
                ci_nxt = op_i;
                cj_nxt = op_j;
                re_valid_nxt = 1;
                re_next_player_id_nxt = player_id;
                S_nxt = S_CH_RE;
            end
        end
        S_CH_RE: begin
            if (re_fire) begin
                op_ready_nxt = 1;
                re_valid_nxt = 0;
                re_next_player_id_nxt = 0;
                S_nxt = S_JCH_OP;
            end
        end
        S_JCH_OP: begin
            if (op_fire) begin
                op_ready_nxt = 0;
                if (occupied[op_ij2idx]) begin
                    ci_nxt = op_i;
                    cj_nxt = op_j;
                    re_valid_nxt = 1;
                    re_next_player_id_nxt = player_id;
                    S_nxt = S_CH_RE;
                end
                else begin
                    ji_nxt = op_i;
                    jj_nxt = op_j;
                    S_nxt = S_J_MV;
                end
            end
        end
        S_J_MV: begin
            occupied_nxt[jij2idx] = 1;
            occupied_nxt[cij2idx] = 0;
            occupied_nxt[($signed(ci) + i_dist/2) * 6 + ($signed(cj) + j_dist/2)] = 0;
            if (ji < ci) begin
                dir_nxt = NORTH;
            end
            else if (jj > cj) begin
                dir_nxt = EAST;
            end
            else if (ji > ci) begin
                dir_nxt = SOUTH;
            end
            else if (jj < cj) begin
                dir_nxt = WEST;
            end
            step_count_nxt = step_count + 1;
            ui_nxt = 0;
            uj_nxt = 0;
            S_nxt = S_J_UPDATE;
        end
        S_J_UPDATE: begin
            N_canjump_nxt[uij2idx] = (ui > 1) && (~occupied[(ui - 2) * 6 + (uj    )]) && (occupied[(ui - 1) * 6 + (uj    )]) && (occupied[uij2idx]);
            E_canjump_nxt[uij2idx] = (uj < 4) && (~occupied[(ui    ) * 6 + (uj + 2)]) && (occupied[(ui    ) * 6 + (uj + 1)]) && (occupied[uij2idx]);
            S_canjump_nxt[uij2idx] = (ui < 4) && (~occupied[(ui + 2) * 6 + (uj    )]) && (occupied[(ui + 1) * 6 + (uj    )]) && (occupied[uij2idx]);
            W_canjump_nxt[uij2idx] = (uj > 1) && (~occupied[(ui    ) * 6 + (uj - 2)]) && (occupied[(ui    ) * 6 + (uj - 1)]) && (occupied[uij2idx]);
            // The ui, uj indicate the position testing now. In this state, the ui, uj will go through all position

            // uj needs to count 0 to 5 again and again, increases by 1 or wrap to zero each cycle.
            uj_nxt = (uj == 5) ? 0 : uj + 1;
            // ui needs to count 0 to 5, but only increases by 1 at uj == 5, holds the same value when uj is still running in the same row.
            ui_nxt = (uj == 5) ? ui + 1 : ui;

            if (ui == 5 && uj == 5) begin
                S_nxt = S_J_JUDGE;
            end
            else begin
                S_nxt = S_J_UPDATE;
            end
        end
        S_J_JUDGE: begin
            if (
                ((dir == NORTH) && (N_canjump[jij2idx])) ||
                ((dir == EAST ) && (E_canjump[jij2idx])) ||
                ((dir == SOUTH) && (S_canjump[jij2idx])) ||
                ((dir == WEST ) && (W_canjump[jij2idx]))
            ) begin
                re_valid_nxt = 1;
                ci_nxt = ji;
                cj_nxt = jj;
                re_is_finished_nxt = (player_id == WHITE && black_no_move) || (player_id == BLACK && white_no_move);
                re_next_player_id_nxt = player_id;
                S_nxt = S_J_STILL_RE;
            end
            else begin
                re_valid_nxt = 1;
                ci_nxt = 0;
                cj_nxt = 0;
                re_is_finished_nxt = (player_id == WHITE && black_no_move) || (player_id == BLACK && white_no_move);
                re_next_player_id_nxt = ~player_id;
                S_nxt = S_J_NOMOVE_RE;
            end
        end
        S_J_NOMOVE_RE: begin
            if (re_fire) begin
                re_valid_nxt = 0;
                op_ready_nxt = 1;
                if (re_is_finished) begin
                    S_nxt = S_CH_OP;

                    player_id_nxt = BLACK;
                    ci_nxt = 0;
                    cj_nxt = 0;
                    ji_nxt = 0;
                    jj_nxt = 0;
                    ui_nxt = 0;
                    uj_nxt = 0;
                    dir_nxt = 0;
                    step_count_nxt = 0;
                    if (step_count < best_step)
                        best_step_nxt = step_count;

                    for (i = 0; i < 36; i = i + 1) begin
                        occupied_nxt[i]  = (i == 14 || i == 15) ? 0 : 1;
                        N_canjump_nxt[i] = (i == 26 || i == 27) ? 1 : 0;
                        E_canjump_nxt[i] = (i == 12           ) ? 1 : 0;
                        S_canjump_nxt[i] = (i ==  2 || i ==  3) ? 1 : 0;
                        W_canjump_nxt[i] = (i == 17           ) ? 1 : 0;
                    end
                end
                else begin
                    player_id_nxt = ~player_id;
                end
                S_nxt = S_CH_OP;
            end
        end
        S_J_STILL_RE: begin//cannot continue, then reset
            if (re_fire) begin
                re_valid_nxt = 0;
                op_ready_nxt = 1;
                if (re_is_finished) begin
                    S_nxt = S_CH_OP;

                    if (step_count < best_step)
                        best_step_nxt = step_count;
                    
                    player_id_nxt = BLACK;
                    ci_nxt = 0;
                    cj_nxt = 0;
                    ji_nxt = 0;
                    jj_nxt = 0;
                    ui_nxt = 0;
                    uj_nxt = 0;
                    dir_nxt = 0;
                    step_count_nxt = 0;                    

                    for (i = 0; i < 36; i = i + 1) begin
                        occupied_nxt[i]  = (i == 14 || i == 15) ? 0 : 1;
                        N_canjump_nxt[i] = (i == 26 || i == 27) ? 1 : 0;
                        E_canjump_nxt[i] = (i == 12           ) ? 1 : 0;
                        S_canjump_nxt[i] = (i ==  2 || i ==  3) ? 1 : 0;
                        W_canjump_nxt[i] = (i == 17           ) ? 1 : 0;
                    end
                end
                else begin
                    S_nxt = S_JN_OP;
                end
            end
        end
        S_JN_OP: begin//next operation
            if (op_fire) begin
                op_ready_nxt = 0;//no new command accept
                if (op_i < 0 || op_j < 0) begin//select to place out of the board
                    re_valid_nxt = 1;
                    ci_nxt = 0;
                    cj_nxt = 0;
                    re_is_finished_nxt = (player_id == WHITE && black_no_move) || (player_id == BLACK && white_no_move);
                    re_next_player_id_nxt = ~player_id;
                    S_nxt = S_J_NOMOVE_RE;
                end
                else begin
                    ji_nxt = op_i;
                    jj_nxt = op_j;
                    S_nxt = S_J_MV;
                end
            end
        end
        default: begin
        end
    endcase
end

always @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        op_ready <= 1;
        re_valid <= 0;
        re_is_finished <= 0;
        re_next_player_id <= 0;

        S <= S_CH_OP;

        player_id <= BLACK;
        ci <= 0;
        cj <= 0;
        ji <= 0;
        jj <= 0;
        ui <= 0;
        uj <= 0;
        dir <= 0;
        
        best_step <= 8'hFF;
        step_count <= 0;

            

        for (i = 0; i < 36; i = i + 1) begin
            occupied[i]  <= (i == 14 || i == 15) ? 0 : 1;
            N_canjump[i] <= (i == 26 || i == 27) ? 1 : 0;
            E_canjump[i] <= (i == 12           ) ? 1 : 0;
            S_canjump[i] <= (i ==  2 || i ==  3) ? 1 : 0;
            W_canjump[i] <= (i == 17           ) ? 1 : 0;
        end
        
    end
    else begin
        op_ready <= op_ready_nxt;
        re_valid <= re_valid_nxt;
        re_is_finished <= re_is_finished_nxt;
        re_next_player_id <= re_next_player_id_nxt;

        S <= S_nxt;
        step_count <= step_count_nxt;
        best_step <= best_step_nxt;
        player_id <= player_id_nxt;
        ci <= ci_nxt;
        cj <= cj_nxt;
        ji <= ji_nxt;
        jj <= jj_nxt;
        ui <= ui_nxt;
        uj <= uj_nxt;
        dir <= dir_nxt;
        
        occupied <= occupied_nxt;
        N_canjump <= N_canjump_nxt;
        E_canjump <= E_canjump_nxt;
        S_canjump <= S_canjump_nxt;
        W_canjump <= W_canjump_nxt;


    end
end

always @(*) begin
    case (S)
        S_CH_RE: begin
            re_selectable = all_cij_can_jumpto | ((player_id == BLACK ? black_movable_all : white_movable_all));
            re_player_can_giveup = 0;
        end
        S_J_NOMOVE_RE: begin
            re_selectable = (re_next_player_id == BLACK) ? black_movable_all : white_movable_all;
            re_player_can_giveup = 0;
        end
        S_J_STILL_RE: begin
            if (re_is_finished) begin
                re_selectable = 36'b000000000100000000000001000000000100;
                re_player_can_giveup = 0;
            end
            else begin
                case (dir)
                    NORTH  : re_selectable = N_cij_can_jumpto;
                    EAST   : re_selectable = E_cij_can_jumpto;
                    SOUTH  : re_selectable = S_cij_can_jumpto;
                    WEST   : re_selectable = W_cij_can_jumpto;
                    default: re_selectable = 0;
                endcase
                re_player_can_giveup = 1;
            end
        end
        default: begin
            re_selectable = 0;
            re_player_can_giveup = 0;
        end
    endcase
end

endmodule