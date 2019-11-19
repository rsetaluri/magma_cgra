/*=============================================================================
** Module: glb_tile.sv
** Description:
**              Global Buffer Tile
** Author: Taeyoung Kong
** Change history: 10/08/2019 - Implement first version of global buffer tile
**===========================================================================*/
import global_buffer_pkg::*;

module glb_tile (
    input  logic                            clk,
    input  logic                            clk_en,
    input  logic                            reset,
    input  logic [TILE_SEL_ADDR_WIDTH-1:0]  glb_tile_id,

    // cgra start/done
    input  logic                            cgra_start_pulse,
    output logic                            cgra_done_pulse,

    // config start/done
    input  logic                            config_start_pulse,
    output logic                            config_done_pulse,

    // Config
    input  logic                            glb_config_wr,
    input  logic                            glb_config_rd,
    input  logic [GLB_CFG_ADDR_WIDTH-1:0]   glb_config_addr,
    input  logic [CONFIG_DATA_WIDTH-1:0]    glb_config_wr_data,
    output logic [CONFIG_DATA_WIDTH-1:0]    glb_config_rd_data,

    // Glb SRAM Config
    input  logic                            glb_sram_config_wr,
    input  logic                            glb_sram_config_rd,
    input  logic [CFG_ADDR_WIDTH-1:0]       glb_sram_config_addr,
    input  logic [CFG_DATA_WIDTH-1:0]       glb_sram_config_wr_data,
    output logic [CFG_DATA_WIDTH-1:0]       glb_sram_config_rd_data,

    // East - host
    input  logic                            h2b_wr_en_esti,
    input  logic [BANK_DATA_WIDTH/8-1:0]    h2b_wr_strb_esti,
    input  logic [GLB_ADDR_WIDTH-1:0]       h2b_wr_addr_esti,
    input  logic [BANK_DATA_WIDTH-1:0]      h2b_wr_data_esti,
    input  logic                            h2b_rd_en_esti,
    input  logic [GLB_ADDR_WIDTH-1:0]       h2b_rd_addr_esti,
    output logic [BANK_DATA_WIDTH-1:0]      b2h_rd_data_esto,

    // West - host
    output logic                            h2b_wr_en_wsto,
    output logic [BANK_DATA_WIDTH/8-1:0]    h2b_wr_strb_wsto,
    output logic [GLB_ADDR_WIDTH-1:0]       h2b_wr_addr_wsto,
    output logic [BANK_DATA_WIDTH-1:0]      h2b_wr_data_wsto,
    output logic                            h2b_rd_en_wsto,
    output logic [GLB_ADDR_WIDTH-1:0]       h2b_rd_addr_wsto,
    input  logic [BANK_DATA_WIDTH-1:0]      b2h_rd_data_wsti,

    // West - fbrc
    input  logic                            f2b_wr_en_wsti,
    input  logic [BANK_DATA_WIDTH-1:0]      f2b_wr_data_wsti,
    input  logic [BANK_DATA_WIDTH-1:0]      f2b_wr_data_bit_sel_wsti,
    input  logic                            f2b_rd_en_wsti,
    input  logic [GLB_ADDR_WIDTH-1:0]       f2b_addr_wsti,
    output logic [BANK_DATA_WIDTH-1:0]      b2f_rd_data_wsto,
    output logic                            b2f_rd_data_valid_wsto,

    // East - fbrc
    output logic                            f2b_wr_en_esto,
    output logic [BANK_DATA_WIDTH-1:0]      f2b_wr_data_esto,
    output logic [BANK_DATA_WIDTH-1:0]      f2b_wr_data_bit_sel_esto,
    output logic                            f2b_rd_en_esto,
    output logic [GLB_ADDR_WIDTH-1:0]       f2b_addr_esto,
    input  logic [BANK_DATA_WIDTH-1:0]      b2f_rd_data_esti,
    input  logic                            b2f_rd_data_valid_esti,

    // South - fbrc
    input  logic                            f2b_wr_en_sthi,
    input  logic [CGRA_DATA_WIDTH-1:0]      f2b_wr_word_sthi,
    input  logic                            f2b_rd_en_sthi,
    input  logic [CGRA_DATA_WIDTH-1:0]      f2b_addr_high_sthi,
    input  logic [CGRA_DATA_WIDTH-1:0]      f2b_addr_low_sthi,
    output logic [CGRA_DATA_WIDTH-1:0]      b2f_rd_word_stho,
    output logic                            b2f_rd_word_valid_stho,

    // West - cfg-bank
    input  logic                            c2b_rd_en_wsti,
    input  logic [GLB_ADDR_WIDTH-1:0]       c2b_addr_wsti,
    output logic [BANK_DATA_WIDTH-1:0]      b2c_rd_data_wsto,
    output logic                            b2c_rd_data_valid_wsto,

    // East - cfg-bank
    output logic                            c2b_rd_en_esto,
    output logic [GLB_ADDR_WIDTH-1:0]       c2b_addr_esto,
    input  logic [BANK_DATA_WIDTH-1:0]      b2c_rd_data_esti,
    input  logic                            b2c_rd_data_valid_esti,

    // West - cfg
    input  logic                            c2f_cfg_wr_wsti,
    input  logic [CFG_ADDR_WIDTH-1:0]       c2f_cfg_addr_wsti,
    input  logic [CFG_DATA_WIDTH-1:0]       c2f_cfg_data_wsti,

    // East - cfg
    output logic                            c2f_cfg_wr_esto,
    output logic [CFG_ADDR_WIDTH-1:0]       c2f_cfg_addr_esto,
    output logic [CFG_DATA_WIDTH-1:0]       c2f_cfg_data_esto,

    // South - cfg
    output logic                            c2f_cfg_wr,
    output logic [CFG_ADDR_WIDTH-1:0]       c2f_cfg_addr,
    output logic [CFG_DATA_WIDTH-1:0]       c2f_cfg_data
);

//============================================================================//
// global buffer sram configuration signal 
//============================================================================//
logic                           glb_sram_config_en_tile;
logic                           glb_sram_config_en_bank [0:NUM_BANKS-1];
logic [BANK_ADDR_WIDTH-1:0]     glb_sram_config_addr_bank;
logic [BANK_SEL_ADDR_WIDTH-1:0] glb_sram_config_bank_sel;
logic [TILE_SEL_ADDR_WIDTH-1:0] glb_sram_config_tile_sel;
logic [CFG_DATA_WIDTH-1:0]      glb_sram_config_rd_data_bank [0:NUM_BANKS-1];

assign glb_sram_config_addr_bank = glb_sram_config_addr[0 +: BANK_ADDR_WIDTH];
assign glb_sram_config_bank_sel = glb_sram_config_addr[BANK_ADDR_WIDTH +: BANK_SEL_ADDR_WIDTH];
assign glb_sram_config_tile_sel = glb_sram_config_addr[BANK_ADDR_WIDTH + BANK_SEL_ADDR_WIDTH +: TILE_SEL_ADDR_WIDTH];
assign glb_sram_config_en_tile = (glb_tile_id == glb_sram_config_tile_sel);

always_comb begin
    for (int i=0; i<NUM_BANKS; i=i+1) begin
        glb_sram_config_en_bank[i] = glb_sram_config_en_tile && (i == glb_sram_config_bank_sel);
    end
end

always_comb begin       
    if (glb_sram_config_rd) begin
        glb_sram_config_rd_data = glb_sram_config_rd_data_bank[glb_sram_config_bank_sel];
    end
    else begin
        glb_sram_config_rd_data = 0;
    end
end

//============================================================================//
// global buffer configuration signal 
//============================================================================//
localparam int GLB_CFG_FEATURE_REG_WIDTH = GLB_CFG_FEATURE_WIDTH + GLB_CFG_REG_WIDTH;
localparam int GLB_CONFIG_FBRC = 0;
localparam int GLB_CONFIG_CFG = 0;

logic                               glb_config_tile_en;
logic                               glb_config_fbrc_en;
logic [GLB_CFG_TILE_WIDTH-1:0]      glb_config_tile_addr;
logic [GLB_CFG_FEATURE_WIDTH-1:0]   glb_config_feature_addr;
logic [GLB_CFG_REG_WIDTH-1:0]       glb_config_reg_addr;
logic [CFG_DATA_WIDTH-1:0]          glb_config_rd_data_fbrc;
logic                               glb_config_wr_fbrc;
logic                               glb_config_rd_fbrc;

logic [CFG_DATA_WIDTH-1:0]          glb_config_rd_data_cfg;
logic                               glb_config_wr_cfg;
logic                               glb_config_rd_cfg;

assign glb_config_tile_addr = glb_config_addr[GLB_CFG_BYTE_OFFSET + GLB_CFG_FEATURE_REG_WIDTH +: GLB_CFG_TILE_WIDTH];
assign glb_config_feature_addr = glb_config_addr[GLB_CFG_BYTE_OFFSET + GLB_CFG_REG_WIDTH +: GLB_CFG_FEATURE_WIDTH];
assign glb_config_reg_addr = glb_config_addr[GLB_CFG_BYTE_OFFSET +: GLB_CFG_REG_WIDTH];

assign glb_config_tile_en = (glb_config_tile_addr == glb_tile_id);
assign glb_config_fbrc_en = glb_config_tile_en && (glb_config_feature_addr == GLB_CONFIG_FBRC);
assign glb_config_cfg_en = glb_config_tile_en && (glb_config_feature_addr == GLB_CONFIG_CFG);

assign glb_config_wr_fbrc = glb_config_fbrc_en && glb_config_wr;
assign glb_config_rd_fbrc = glb_config_fbrc_en && glb_config_rd;

assign glb_config_wr_cfg = glb_config_cfg_en && glb_config_wr;
assign glb_config_rd_cfg = glb_config_cfg_en && glb_config_rd;

always_comb begin       
    if (glb_config_rd_fbrc) begin
        glb_config_rd_data = glb_config_rd_data_fbrc;
    end
    else if (glb_config_rd_cfg) begin
        glb_config_rd_data = glb_config_rd_data_cfg;
    end
    else begin
        glb_config_rd_data = 0;
    end
end

//============================================================================//
// internal wire declaration
//============================================================================//
logic                       h2b_wr_en [0:NUM_BANKS-1];
logic [BANK_DATA_WIDTH-1:0] h2b_wr_data [0:NUM_BANKS-1];
logic [BANK_DATA_WIDTH-1:0] h2b_wr_data_bit_sel [0:NUM_BANKS-1];
logic [BANK_ADDR_WIDTH-1:0] h2b_wr_addr [0:NUM_BANKS-1];
logic                       h2b_rd_en [0:NUM_BANKS-1];
logic [BANK_ADDR_WIDTH-1:0] h2b_rd_addr [0:NUM_BANKS-1];
logic [BANK_DATA_WIDTH-1:0] b2h_rd_data [0:NUM_BANKS-1];

logic                       f2b_wr_en [0:NUM_BANKS-1];
logic [BANK_DATA_WIDTH-1:0] f2b_wr_data [0:NUM_BANKS-1];
logic [BANK_DATA_WIDTH-1:0] f2b_wr_data_bit_sel [0:NUM_BANKS-1];
logic [BANK_ADDR_WIDTH-1:0] f2b_wr_addr [0:NUM_BANKS-1];
logic                       f2b_rd_en [0:NUM_BANKS-1];
logic [BANK_ADDR_WIDTH-1:0] f2b_rd_addr [0:NUM_BANKS-1];
logic [BANK_DATA_WIDTH-1:0] b2f_rd_data [0:NUM_BANKS-1];

logic                       c2b_rd_en [0:NUM_BANKS-1];
logic [BANK_ADDR_WIDTH-1:0] c2b_rd_addr [0:NUM_BANKS-1];
logic [BANK_DATA_WIDTH-1:0] b2c_rd_data [0:NUM_BANKS-1];

//============================================================================//
// glb_host_interconnect
//============================================================================//
glb_host_interconnect glb_host_interconnect_inst (
    .clk(clk),
    .reset(reset),
    .glb_tile_id(glb_tile_id),

    .h2b_wr_en_esti(h2b_wr_en_esti),
    .h2b_wr_strb_esti(h2b_wr_strb_esti),
    .h2b_wr_data_esti(h2b_wr_data_esti),
    .h2b_wr_addr_esti(h2b_wr_addr_esti),
    .h2b_rd_en_esti(h2b_rd_en_esti),
    .h2b_rd_addr_esti(h2b_rd_addr_esti),
    .b2h_rd_data_esto(b2h_rd_data_esto),

    .h2b_wr_en_wsto(h2b_wr_en_wsto),
    .h2b_wr_strb_wsto(h2b_wr_strb_wsto),
    .h2b_wr_addr_wsto(h2b_wr_addr_wsto),
    .h2b_wr_data_wsto(h2b_wr_data_wsto),
    .h2b_rd_en_wsto(h2b_rd_en_wsto),
    .h2b_rd_addr_wsto(h2b_rd_addr_wsto),
    .b2h_rd_data_wsti(b2h_rd_data_wsti),

    .h2b_wr_en(h2b_wr_en),
    .h2b_wr_data(h2b_wr_data),
    .h2b_wr_data_bit_sel(h2b_wr_data_bit_sel),
    .h2b_wr_addr(h2b_wr_addr),
    .h2b_rd_en(h2b_rd_en),
    .h2b_rd_addr(h2b_rd_addr),
    .b2h_rd_data(b2h_rd_data)
);

//============================================================================//
// glb_bank generation
//============================================================================//
genvar i;
generate
for (i=0; i<NUM_BANKS; i=i+1) begin
    glb_bank glb_bank_inst (
        .clk(clk),
        .reset(reset),

        .host_wr_en(h2b_wr_en[i]),
        .host_wr_data(h2b_wr_data[i]),
        .host_wr_data_bit_sel(h2b_wr_data_bit_sel[i]),
        .host_wr_addr(h2b_wr_addr[i]),
        .host_rd_en(h2b_rd_en[i]),
        .host_rd_data(b2h_rd_data[i]),
        .host_rd_addr(h2b_rd_addr[i]),

        .cgra_wr_en(f2b_wr_en[i]),
        .cgra_wr_data(f2b_wr_data[i]),
        .cgra_wr_data_bit_sel(f2b_wr_data_bit_sel[i]),
        .cgra_wr_addr(f2b_wr_addr[i]),
        .cgra_rd_en(f2b_rd_en[i]),
        .cgra_rd_data(b2f_rd_data[i]),
        .cgra_rd_addr(f2b_rd_addr[i]),

        .cfg_rd_en(c2b_rd_en[i]),
        .cfg_rd_data(b2c_rd_data[i]),
        .cfg_rd_addr(c2b_rd_addr[i]),

        .config_en(glb_sram_config_en_bank[i]),
        .config_wr(glb_sram_config_wr),
        .config_rd(glb_sram_config_rd),
        .config_addr(glb_sram_config_addr_bank),
        .config_wr_data(glb_sram_config_wr_data),
        .config_rd_data(glb_sram_config_rd_data_bank[i])
    );
end
endgenerate

//============================================================================//
// glb_fbrc_interconnect
//============================================================================//
glb_fbrc_interconnect glb_fbrc_interconnect_inst (
    .clk(clk),
    .clk_en(clk_en),
    .reset(reset),
    .glb_tile_id(glb_tile_id),

    .cgra_start_pulse(cgra_start_pulse),
    .cgra_done_pulse(cgra_done_pulse),

    // config
    .config_wr(glb_config_wr_fbrc),
    .config_rd(glb_config_rd_fbrc),
    .config_addr(glb_config_reg_addr),
    .config_wr_data(glb_config_wr_data),
    .config_rd_data(glb_config_rd_data_fbrc),

    // West
    .f2b_wr_en_wsti(f2b_wr_en_wsti),
    .f2b_wr_data_wsti(f2b_wr_data_wsti),
    .f2b_wr_data_bit_sel_wsti(f2b_wr_data_bit_sel_wsti),
    .f2b_rd_en_wsti(f2b_rd_en_wsti),
    .f2b_addr_wsti(f2b_addr_wsti),
    .b2f_rd_data_wsto(b2f_rd_data_wsto),
    .b2f_rd_data_valid_wsto(b2f_rd_data_valid_wsto),

    // East
    .f2b_wr_en_esto(f2b_wr_en_esto),
    .f2b_wr_data_esto(f2b_wr_data_esto),
    .f2b_wr_data_bit_sel_esto(f2b_wr_data_bit_sel_esto),
    .f2b_rd_en_esto(f2b_rd_en_esto),
    .f2b_addr_esto(f2b_addr_esto),
    .b2f_rd_data_esti(b2f_rd_data_esti),
    .b2f_rd_data_valid_esti(b2f_rd_data_valid_esti),

    // South
    .f2b_wr_en_sthi(f2b_wr_en_sthi),
    .f2b_wr_word_sthi(f2b_wr_word_sthi),
    .f2b_rd_en_sthi(f2b_rd_en_sthi),
    .f2b_addr_high_sthi(f2b_addr_high_sthi),
    .f2b_addr_low_sthi(f2b_addr_low_sthi),
    .b2f_rd_word_stho(b2f_rd_word_stho),
    .b2f_rd_word_valid_stho(b2f_rd_word_valid_stho),

    // Bank
    .f2b_wr_en(f2b_wr_en),
    .f2b_wr_data(f2b_wr_data),
    .f2b_wr_addr(f2b_wr_addr),
    .f2b_wr_data_bit_sel(f2b_wr_data_bit_sel),
    .f2b_rd_en(f2b_rd_en),
    .f2b_rd_addr(f2b_rd_addr),
    .b2f_rd_data(b2f_rd_data)
);

//============================================================================//
// glb_cfg_interconnect
//============================================================================//
glb_cfg_interconnect glb_cfg_interconnect_inst (
    .clk(clk),
    .reset(reset),
    .glb_tile_id(glb_tile_id),

    .config_start_pulse(config_start_pulse),
    .config_done_pulse(config_done_pulse),

    // config
    .config_wr(glb_config_wr_cfg),
    .config_rd(glb_config_rd_cfg),
    .config_addr(glb_config_reg_addr),
    .config_wr_data(glb_config_wr_data),
    .config_rd_data(glb_config_rd_data_cfg),

    // West
    .c2b_rd_en_wsti(c2b_rd_en_wsti),
    .c2b_addr_wsti(c2b_addr_wsti),
    .b2c_rd_data_wsto(b2c_rd_data_wsto),
    .b2c_rd_data_valid_wsto(b2c_rd_data_valid_wsto),

    // East
    .c2b_rd_en_esto(c2b_rd_en_esto),
    .c2b_addr_esto(c2b_addr_esto),
    .b2c_rd_data_esti(b2c_rd_data_esti),
    .b2c_rd_data_valid_esti(b2c_rd_data_valid_esti),

    // Bank
    .c2b_rd_en(c2b_rd_en),
    .c2b_rd_addr(c2b_rd_addr),
    .b2c_rd_data(b2c_rd_data),

    // fbrc cfg
    .c2f_cfg_wr(c2f_cfg_wr),
    .c2f_cfg_addr(c2f_cfg_addr),
    .c2f_cfg_data(c2f_cfg_data),

    // fbrc cfg west in
    .c2f_cfg_wr_wsti(c2f_cfg_wr_wsti),
    .c2f_cfg_addr_wsti(c2f_cfg_addr_wsti),
    .c2f_cfg_data_wsti(c2f_cfg_data_wsti),

    // fbrc cfg east out
    .c2f_cfg_wr_esto(c2f_cfg_wr_esto),
    .c2f_cfg_addr_esto(c2f_cfg_addr_esto),
    .c2f_cfg_data_esto(c2f_cfg_data_esto)
);

endmodule
