// 文件：global_def.v
// 职责：定义SDRAM数据、地址与模式常量。
// 来源与修改说明：参见SOURCE_ORIGIN.md。



`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`define	  SDR_CLK_PERIOD				24
`define   SELF_REFRESH_INTERVAL			64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)

