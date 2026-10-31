//==============================================================================
// File        : lcd_display.v
// Module      : lcd_display
// Description :
//   On-screen UI renderer. It draws the mode buttons, parameter sliders and decimal values as
//   well as the live video frame, and maps the defined touch zones to the UI controls.
//==============================================================================
module lcd_display(
    input             lcd_pclk,
    input             sys_rst_n,
    input      [31:0] data,
    input      [10:0] pixel_xpos,
    input      [10:0] pixel_ypos,
    output reg [23:0] pixel_data,
    output reg [1:0]  mode_switch_signal,
    output reg [5:0]  frame_switching_signal,
    output reg [2:0]  sens_level,
    output reg [15:0]  thresh_lvl,
    output reg         calc_mode,
    input      [15:0] amp_pix,
    input             touch_valid
);
reg [31:0] font32 [0:319];
initial begin
font32[0] = 32'h00000000; font32[1] = 32'h00000000; font32[2] = 32'h00000020; font32[3] = 32'h00000070;
font32[4] = 32'h03FFFFF8; font32[5] = 32'h03004000; font32[6] = 32'h03006000; font32[7] = 32'h03004000;
font32[8] = 32'h03008040; font32[9] = 32'h031FFFE0; font32[10] = 32'h03180040; font32[11] = 32'h03180040;
font32[12] = 32'h03180040; font32[13] = 32'h031FFFC0; font32[14] = 32'h03180040; font32[15] = 32'h03180040;
font32[16] = 32'h03180040; font32[17] = 32'h03180040; font32[18] = 32'h021FFFC0; font32[19] = 32'h02183040;
font32[20] = 32'h02003000; font32[21] = 32'h02003000; font32[22] = 32'h06063400; font32[23] = 32'h060F3380;
font32[24] = 32'h060C30E0; font32[25] = 32'h04183078; font32[26] = 32'h0C203038; font32[27] = 32'h08C03018;
font32[28] = 32'h1183F008; font32[29] = 32'h1000E000; font32[30] = 32'h20004000; font32[31] = 32'h00000000;
font32[32] = 32'h00000000; font32[33] = 32'h00000000; font32[34] = 32'h01000800; font32[35] = 32'h01C00E00;
font32[36] = 32'h01801C00; font32[37] = 32'h01801800; font32[38] = 32'h01801000; font32[39] = 32'h03003000;
font32[40] = 32'h030020C0; font32[41] = 32'h03086060; font32[42] = 32'h3FFC4038; font32[43] = 32'h0208801C;
font32[44] = 32'h061981FC; font32[45] = 32'h0619FE0C; font32[46] = 32'h04198008; font32[47] = 32'h04180000;
font32[48] = 32'h0C100000; font32[49] = 32'h0C308010; font32[50] = 32'h0830FFF8; font32[51] = 32'h1820C030;
font32[52] = 32'h1860C030; font32[53] = 32'h0C60C030; font32[54] = 32'h0340C030; font32[55] = 32'h00E0C030;
font32[56] = 32'h00B8C030; font32[57] = 32'h019CC030; font32[58] = 32'h030CC030; font32[59] = 32'h0600FFF0;
font32[60] = 32'h0C00C030; font32[61] = 32'h1000C030; font32[62] = 32'h20008000; font32[63] = 32'h00000000;
font32[64] = 32'h00000000; font32[65] = 32'h00000000; font32[66] = 32'h04000000; font32[67] = 32'h03000020;
font32[68] = 32'h0381FFF0; font32[69] = 32'h01818060; font32[70] = 32'h01818060; font32[71] = 32'h01218060;
font32[72] = 32'h3FF18860; font32[73] = 32'h00618E60; font32[74] = 32'h00618C60; font32[75] = 32'h00C18C60;
font32[76] = 32'h00C18C60; font32[77] = 32'h01818C60; font32[78] = 32'h01818C60; font32[79] = 32'h03818C60;
font32[80] = 32'h07E18860; font32[81] = 32'h05B98860; font32[82] = 32'h09998C60; font32[83] = 32'h11981F00;
font32[84] = 32'h21881E00; font32[85] = 32'h41801600; font32[86] = 32'h01803600; font32[87] = 32'h01803600;
font32[88] = 32'h01806604; font32[89] = 32'h0180C604; font32[90] = 32'h01808604; font32[91] = 32'h0183060C;
font32[92] = 32'h018607FE; font32[93] = 32'h019803F8; font32[94] = 32'h01200000; font32[95] = 32'h00000000;
font32[96] = 32'h00000000; font32[97] = 32'h00000000; font32[98] = 32'h00400000; font32[99] = 32'h00600008;
font32[100] = 32'h0061FFFC; font32[101] = 32'h00600300; font32[102] = 32'h06600600; font32[103] = 32'h06640400;
font32[104] = 32'h067E0408; font32[105] = 32'h06607FFC; font32[106] = 32'h06606018; font32[107] = 32'h06606018;
font32[108] = 32'h06626218; font32[109] = 32'h3FFF6398; font32[110] = 32'h00406318; font32[111] = 32'h00606318;
font32[112] = 32'h04406318; font32[113] = 32'h06406318; font32[114] = 32'h06426318; font32[115] = 32'h0C476318;
font32[116] = 32'h0C466318; font32[117] = 32'h184C6218; font32[118] = 32'h104C6218; font32[119] = 32'h20180700;
font32[120] = 32'h20300480; font32[121] = 32'h00600C60; font32[122] = 32'h00C01838; font32[123] = 32'h0180301C;
font32[124] = 32'h0600600C; font32[125] = 32'h08018004; font32[126] = 32'h30060004; font32[127] = 32'h00000000;
font32[128] = 32'h00000000; font32[129] = 32'h00000000; font32[130] = 32'h00000800; font32[131] = 32'h00000E00;
font32[132] = 32'h00000C00; font32[133] = 32'h000C0C00; font32[134] = 32'h1FFE0C00; font32[135] = 32'h00000C00;
font32[136] = 32'h00000C00; font32[137] = 32'h00000C00; font32[138] = 32'h0000FFFC; font32[139] = 32'h00020C18;
font32[140] = 32'h3FFF0C18; font32[141] = 32'h00800C18; font32[142] = 32'h01E00C18; font32[143] = 32'h01800C18;
font32[144] = 32'h03000818; font32[145] = 32'h03000818; font32[146] = 32'h06101818; font32[147] = 32'h04081818;
font32[148] = 32'h0C0C1018; font32[149] = 32'h08061018; font32[150] = 32'h107F3010; font32[151] = 32'h3F832010;
font32[152] = 32'h38026010; font32[153] = 32'h0000C030; font32[154] = 32'h00018030; font32[155] = 32'h00010C30;
font32[156] = 32'h000603E0; font32[157] = 32'h000801E0; font32[158] = 32'h00100080; font32[159] = 32'h00000000;
font32[160] = 32'h00000000; font32[161] = 32'h00000000; font32[162] = 32'h00020000; font32[163] = 32'h00038000;
font32[164] = 32'h00030000; font32[165] = 32'h00030000; font32[166] = 32'h00030000; font32[167] = 32'h00030030;
font32[168] = 32'h3FFFFFF8; font32[169] = 32'h00068000; font32[170] = 32'h00064000; font32[171] = 32'h00064000;
font32[172] = 32'h000C2000; font32[173] = 32'h000C1000; font32[174] = 32'h00181800; font32[175] = 32'h003C0E00;
font32[176] = 32'h00670780; font32[177] = 32'h018381F0; font32[178] = 32'h0701C0FC; font32[179] = 32'h1800C030;
font32[180] = 32'h60640000; font32[181] = 32'h00738000; font32[182] = 32'h0261C080; font32[183] = 32'h0660C460;
font32[184] = 32'h04608470; font32[185] = 32'h0C600438; font32[186] = 32'h1C600430; font32[187] = 32'h38600610;
font32[188] = 32'h0037FF00; font32[189] = 32'h003FFE00; font32[190] = 32'h00000000; font32[191] = 32'h00000000;
font32[192] = 32'h00000000; font32[193] = 32'h00000000; font32[194] = 32'h02000000; font32[195] = 32'h03800040;
font32[196] = 32'h0301FFE0; font32[197] = 32'h030100C0; font32[198] = 32'h030100C0; font32[199] = 32'h030100C0;
font32[200] = 32'h0331FFC0; font32[201] = 32'h3FF900C0; font32[202] = 32'h030100C0; font32[203] = 32'h030100C0;
font32[204] = 32'h030100C0; font32[205] = 32'h0301FFC0; font32[206] = 32'h031100C0; font32[207] = 32'h03610018;
font32[208] = 32'h03BFFFFC; font32[209] = 32'h0F000800; font32[210] = 32'h7F000800; font32[211] = 32'h33070800;
font32[212] = 32'h03060800; font32[213] = 32'h03060830; font32[214] = 32'h03060FF8; font32[215] = 32'h03060800;
font32[216] = 32'h030D0800; font32[217] = 32'h030C8800; font32[218] = 32'h03184800; font32[219] = 32'h03103C02;
font32[220] = 32'h1F201FFC; font32[221] = 32'h064003F0; font32[222] = 32'h00800000; font32[223] = 32'h00000000;
font32[224] = 32'h00000000; font32[225] = 32'h00000000; font32[226] = 32'h00020000; font32[227] = 32'h3FFF8000;
font32[228] = 32'h060C0000; font32[229] = 32'h060C0020; font32[230] = 32'h060DFFF0; font32[231] = 32'h060C4060;
font32[232] = 32'h060C2060; font32[233] = 32'h07FC2060; font32[234] = 32'h060C2060; font32[235] = 32'h060C20C0;
font32[236] = 32'h060C20C0; font32[237] = 32'h060C10C0; font32[238] = 32'h060C1080; font32[239] = 32'h060C1180;
font32[240] = 32'h07FC1980; font32[241] = 32'h060C0B00; font32[242] = 32'h060C0B00; font32[243] = 32'h060C0F00;
font32[244] = 32'h060F8600; font32[245] = 32'h061C0600; font32[246] = 32'h07EC0F00; font32[247] = 32'h3F0C0B00;
font32[248] = 32'h380C1980; font32[249] = 32'h000C30E0; font32[250] = 32'h000C2070; font32[251] = 32'h000C403E;
font32[252] = 32'h000C8018; font32[253] = 32'h000D0000; font32[254] = 32'h000A0000; font32[255] = 32'h00000000;
font32[256] = 32'h00000000; font32[257] = 32'h00000000; font32[258] = 32'h00010080; font32[259] = 32'h0300C0C0;
font32[260] = 32'h03006180; font32[261] = 32'h03006100; font32[262] = 32'h03002210; font32[263] = 32'h0307FFF8;
font32[264] = 32'h03040818; font32[265] = 32'h03040818; font32[266] = 32'h036588F8; font32[267] = 32'h3FF4C8D8;
font32[268] = 32'h0304C998; font32[269] = 32'h03044918; font32[270] = 32'h03044A18; font32[271] = 32'h03040818;
font32[272] = 32'h0307FFF8; font32[273] = 32'h03040018; font32[274] = 32'h03000000; font32[275] = 32'h03020020;
font32[276] = 32'h0303FFF0; font32[277] = 32'h03130060; font32[278] = 32'h03E30060; font32[279] = 32'h07030060;
font32[280] = 32'h7C03FFE0; font32[281] = 32'h30030060; font32[282] = 32'h00030060; font32[283] = 32'h00030060;
font32[284] = 32'h0003FFE0; font32[285] = 32'h00030060; font32[286] = 32'h00020040; font32[287] = 32'h00000000;
font32[288] = 32'h00000000; font32[289] = 32'h00000000; font32[290] = 32'h00000000; font32[291] = 32'h00010020;
font32[292] = 32'h0021FFF0; font32[293] = 32'h3FF18060; font32[294] = 32'h00218060; font32[295] = 32'h00218060;
font32[296] = 32'h00218060; font32[297] = 32'h0021FFE0; font32[298] = 32'h00218860; font32[299] = 32'h00210E00;
font32[300] = 32'h0FE00C00; font32[301] = 32'h08200C00; font32[302] = 32'h08020C10; font32[303] = 32'h0803FFF8;
font32[304] = 32'h18030C10; font32[305] = 32'h18230C10; font32[306] = 32'h1FF30C10; font32[307] = 32'h10630C10;
font32[308] = 32'h00630C10; font32[309] = 32'h0063FFF0; font32[310] = 32'h00630C10; font32[311] = 32'h00620C00;
font32[312] = 32'h00600C20; font32[313] = 32'h00400C30; font32[314] = 32'h00C00C18; font32[315] = 32'h00C00C7C;
font32[316] = 32'h0F8FFF8C; font32[317] = 32'h078F8004; font32[318] = 32'h02000000; font32[319] = 32'h00000000;
end
reg [7:0] font8 [0:159];
initial begin
font8[0] = 8'h00; font8[1] = 8'h00; font8[2] = 8'h00; font8[3] = 8'h18; font8[4] = 8'h24; font8[5] = 8'h42; font8[6] = 8'h42; font8[7] = 8'h42;
font8[8] = 8'h42; font8[9] = 8'h42; font8[10] = 8'h42; font8[11] = 8'h42; font8[12] = 8'h24; font8[13] = 8'h18; font8[14] = 8'h00; font8[15] = 8'h00;
font8[16] = 8'h00; font8[17] = 8'h00; font8[18] = 8'h00; font8[19] = 8'h08; font8[20] = 8'h38; font8[21] = 8'h08; font8[22] = 8'h08; font8[23] = 8'h08;
font8[24] = 8'h08; font8[25] = 8'h08; font8[26] = 8'h08; font8[27] = 8'h08; font8[28] = 8'h08; font8[29] = 8'h3E; font8[30] = 8'h00; font8[31] = 8'h00;
font8[32] = 8'h00; font8[33] = 8'h00; font8[34] = 8'h00; font8[35] = 8'h3C; font8[36] = 8'h42; font8[37] = 8'h42; font8[38] = 8'h42; font8[39] = 8'h02;
font8[40] = 8'h04; font8[41] = 8'h08; font8[42] = 8'h10; font8[43] = 8'h20; font8[44] = 8'h42; font8[45] = 8'h7E; font8[46] = 8'h00; font8[47] = 8'h00;
font8[48] = 8'h00; font8[49] = 8'h00; font8[50] = 8'h00; font8[51] = 8'h3C; font8[52] = 8'h42; font8[53] = 8'h42; font8[54] = 8'h02; font8[55] = 8'h04;
font8[56] = 8'h18; font8[57] = 8'h04; font8[58] = 8'h02; font8[59] = 8'h42; font8[60] = 8'h42; font8[61] = 8'h3C; font8[62] = 8'h00; font8[63] = 8'h00;
font8[64] = 8'h00; font8[65] = 8'h00; font8[66] = 8'h00; font8[67] = 8'h04; font8[68] = 8'h0C; font8[69] = 8'h14; font8[70] = 8'h24; font8[71] = 8'h24;
font8[72] = 8'h44; font8[73] = 8'h44; font8[74] = 8'h7F; font8[75] = 8'h04; font8[76] = 8'h04; font8[77] = 8'h1F; font8[78] = 8'h00; font8[79] = 8'h00;
font8[80] = 8'h00; font8[81] = 8'h00; font8[82] = 8'h00; font8[83] = 8'h7E; font8[84] = 8'h40; font8[85] = 8'h40; font8[86] = 8'h40; font8[87] = 8'h78;
font8[88] = 8'h44; font8[89] = 8'h02; font8[90] = 8'h02; font8[91] = 8'h42; font8[92] = 8'h44; font8[93] = 8'h38; font8[94] = 8'h00; font8[95] = 8'h00;
font8[96] = 8'h00; font8[97] = 8'h00; font8[98] = 8'h00; font8[99] = 8'h18; font8[100] = 8'h24; font8[101] = 8'h40; font8[102] = 8'h40; font8[103] = 8'h5C;
font8[104] = 8'h62; font8[105] = 8'h42; font8[106] = 8'h42; font8[107] = 8'h42; font8[108] = 8'h22; font8[109] = 8'h1C; font8[110] = 8'h00; font8[111] = 8'h00;
font8[112] = 8'h00; font8[113] = 8'h00; font8[114] = 8'h00; font8[115] = 8'h7E; font8[116] = 8'h42; font8[117] = 8'h04; font8[118] = 8'h04; font8[119] = 8'h08;
font8[120] = 8'h08; font8[121] = 8'h10; font8[122] = 8'h10; font8[123] = 8'h10; font8[124] = 8'h10; font8[125] = 8'h10; font8[126] = 8'h00; font8[127] = 8'h00;
font8[128] = 8'h00; font8[129] = 8'h00; font8[130] = 8'h00; font8[131] = 8'h3C; font8[132] = 8'h42; font8[133] = 8'h42; font8[134] = 8'h42; font8[135] = 8'h24;
font8[136] = 8'h18; font8[137] = 8'h24; font8[138] = 8'h42; font8[139] = 8'h42; font8[140] = 8'h42; font8[141] = 8'h3C; font8[142] = 8'h00; font8[143] = 8'h00;
font8[144] = 8'h00; font8[145] = 8'h00; font8[146] = 8'h00; font8[147] = 8'h38; font8[148] = 8'h44; font8[149] = 8'h42; font8[150] = 8'h42; font8[151] = 8'h42;
font8[152] = 8'h46; font8[153] = 8'h3A; font8[154] = 8'h02; font8[155] = 8'h02; font8[156] = 8'h24; font8[157] = 8'h18; font8[158] = 8'h00; font8[159] = 8'h00;
end
reg [15:0] font16 [0:79];
initial begin
font16[0] = 16'h0008; font16[1] = 16'h003C; font16[2] = 16'hF9E0; font16[3] = 16'h0820; font16[4] = 16'h1020; font16[5] = 16'h1120; font16[6] = 16'h213C; font16[7] = 16'h7920;
font16[8] = 16'h0920; font16[9] = 16'h0920; font16[10] = 16'h4920; font16[11] = 16'h31FC; font16[12] = 16'h1000; font16[13] = 16'h2C00; font16[14] = 16'h43FE; font16[15] = 16'h8000;
font16[16] = 16'h0000; font16[17] = 16'h21F8; font16[18] = 16'h1108; font16[19] = 16'h1108; font16[20] = 16'h0108; font16[21] = 16'h01F8; font16[22] = 16'hF108; font16[23] = 16'h1120;
font16[24] = 16'h1110; font16[25] = 16'h1208; font16[26] = 16'h1204; font16[27] = 16'h1404; font16[28] = 16'h1000; font16[29] = 16'h2800; font16[30] = 16'h47FE; font16[31] = 16'h0000;
font16[32] = 16'h1020; font16[33] = 16'h1020; font16[34] = 16'h103E; font16[35] = 16'h7C20; font16[36] = 16'h5420; font16[37] = 16'h55FC; font16[38] = 16'h5504; font16[39] = 16'h5524;
font16[40] = 16'h5524; font16[41] = 16'h5524; font16[42] = 16'h5524; font16[43] = 16'h5D24; font16[44] = 16'h1050; font16[45] = 16'h1048; font16[46] = 16'h1084; font16[47] = 16'h1104;
font16[48] = 16'h0000; font16[49] = 16'h47FC; font16[50] = 16'h2444; font16[51] = 16'h2444; font16[52] = 16'h05F4; font16[53] = 16'h0444; font16[54] = 16'hE444; font16[55] = 16'h27FC;
font16[56] = 16'h2404; font16[57] = 16'h25F4; font16[58] = 16'h2514; font16[59] = 16'h2D14; font16[60] = 16'h35F4; font16[61] = 16'h2404; font16[62] = 16'h0414; font16[63] = 16'h0808;
font16[64] = 16'h0820; font16[65] = 16'h0820; font16[66] = 16'hFFFE; font16[67] = 16'h0820; font16[68] = 16'h0820; font16[69] = 16'h0000; font16[70] = 16'h7FF8; font16[71] = 16'h0208;
font16[72] = 16'h0208; font16[73] = 16'h0208; font16[74] = 16'h0208; font16[75] = 16'h0250; font16[76] = 16'h0220; font16[77] = 16'h0200; font16[78] = 16'h0200; font16[79] = 16'h0200;
end
localparam BG     = 24'hE0F3FA;
localparam BLACK  = 24'h000000;
localparam WHITE  = 24'hFFFFFF;
localparam GRAY   = 24'hB1B1B1;
localparam EDGE   = 24'hA9A9A9;
localparam BTN1_C = 24'h56BFEC;
localparam BTN2_C = 24'h4AFF50;
localparam BTN3_C = 24'hFF4379;
localparam BTN1_G = 24'h758F9B;
localparam BTN2_G = 24'h729F74;
localparam BTN3_G = 24'h9F707E;
wire [3:0]  x_q = data[31:28];
wire [3:0]  x_b = data[27:24];
wire [3:0]  x_s = data[23:20];
wire [3:0]  x_g = data[19:16];
wire [3:0]  y_b = data[11:8];
wire [3:0]  y_s = data[7:4];
wire [3:0]  y_g = data[3:0];
wire [10:0] touch_x = x_q*1000 + x_b*100 + x_s*10 + x_g;
wire [10:0] touch_y = y_b*100  + y_s*10  + y_g;
wire        touch_p = (data != 32'd0);
reg [1:0] mode;
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        mode <= 2'd0;
    else if(touch_p && touch_y>=11'd165 && touch_y<=11'd305) begin
        if(touch_x>=11'd69  && touch_x<=11'd248) mode <= 2'd0;
        else if(touch_x>=11'd310 && touch_x<=11'd489) mode <= 2'd1;
        else if(touch_x>=11'd551 && touch_x<=11'd730) mode <= 2'd2;
    end
end
reg [5:0] frame;
wire in_slider = touch_p && touch_y>=11'd410 && touch_y<=11'd458
               && touch_x>=11'd140 && touch_x<=11'd660;
wire [10:0] dx = (touch_x<11'd170) ? 11'd0 :
                 (touch_x>11'd630) ? 11'd460 : (touch_x-11'd170);
wire [15:0] fcalc = dx * 16'd59;
wire [5:0]  fnew  = 6'd1 + fcalc/16'd460;
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) frame <= 6'd1;
    else if(in_slider && mode==2'd1) frame <= fnew;
end
reg [2:0] sens;
wire in_slider2 = touch_p && touch_y>=11'd410 && touch_y<=11'd458
               && touch_x>=11'd140 && touch_x<=11'd660;
wire [10:0] dx2 = (touch_x<11'd170) ? 11'd0 :
                  (touch_x>11'd630) ? 11'd460 : (touch_x-11'd170);
wire [15:0] scalc = dx2 * 16'd4;
wire [2:0]  snew  = 3'd1 + scalc/16'd460;
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) sens <= 3'd3;
    else if(in_slider2 && mode==2'd2) sens <= snew;
end
reg [15:0] thresh;
wire in_slider0 = touch_p && touch_y>=11'd370 && touch_y<=11'd390
               && touch_x>=11'd140 && touch_x<=11'd660;
wire [10:0] dx0 = (touch_x<11'd170) ? 11'd0 :
                  (touch_x>11'd630) ? 11'd460 : (touch_x-11'd170);
wire [26:0] tcalc = dx0 * 17'd65535;
wire [15:0] tnew  = tcalc / 17'd460;
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) thresh <= 16'd500;
    else if(in_slider0 && mode==2'd1) thresh <= tnew;
end
reg tv_s0, tv_s1;
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin tv_s0<=1'b0; tv_s1<=1'b0; end
    else begin tv_s0<=touch_valid; tv_s1<=tv_s0; end
end
reg calc_r;
reg calc_done;
wire in_calc_zone = (tv_s1==1'b1) && mode==2'd1 &&
                    touch_x>=11'd355 && touch_x<=11'd445 &&
                    touch_y>=11'd70  && touch_y<=11'd140;
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin calc_r<=1'b0; calc_done<=1'b0; end
    else if(tv_s1==1'b0)
        calc_done<=1'b0;
    else if(in_calc_zone && !calc_done) begin
        calc_r<=~calc_r;
        calc_done<=1'b1;
    end
end
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        mode_switch_signal    <= 2'd0;
        frame_switching_signal<= 6'd1;
        sens_level            <= 3'd3;
        thresh_lvl            <= 16'd500;
        calc_mode             <= 1'b0;
    end else begin
        mode_switch_signal    <= mode;
        frame_switching_signal<= frame;
        sens_level            <= sens;
        thresh_lvl            <= thresh;
        calc_mode             <= calc_r;
    end
end
wire [15:0] knob_ofs = (frame - 6'd1) * 16'd460;
reg  [10:0] knob_x;
wire [10:0] knob_y   = 11'd434;
wire [31:0] knob0_ofs = thresh * 16'd460;
reg  [10:0] knob0_x;
wire [10:0] knob0_y   = 11'd380;
wire [15:0] knob2_ofs = (sens - 3'd1) * 16'd460;
reg  [10:0] knob2_x;
wire [10:0] knob2_y   = 11'd434;
reg  [5:0]  tens;
reg  [3:0]  ones;
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        knob_x  <= 11'd170;
        knob0_x <= 11'd173;
        knob2_x <= 11'd170;
        tens    <= 6'd0;
        ones    <= 4'd1;
    end else begin
        knob_x  <= 11'd170 + knob_ofs  / 16'd59;
        knob0_x <= 11'd170 + knob0_ofs / 17'd65535;
        knob2_x <= 11'd170 + knob2_ofs / 16'd4;
        tens    <= frame / 10;
        ones    <= frame % 10;
    end
end
function in_rrect;
    input [10:0] px,py,x0,y0,x1,y1,r;
    reg [10:0] cx,cy;
    reg [21:0] ddx,ddy;
    begin
        if(px<x0 || px>x1 || py<y0 || py>y1)
            in_rrect = 1'b0;
        else if(px>=x0+r && px<=x1-r)
            in_rrect = 1'b1;
        else if(py>=y0+r && py<=y1-r)
            in_rrect = 1'b1;
        else begin
            cx = (px<x0+r) ? x0+r : x1-r;
            cy = (py<y0+r) ? y0+r : y1-r;
            ddx = (px>cx)?(px-cx):(cx-px);
            ddy = (py>cy)?(py-cy):(cy-py);
            in_rrect = (ddx*ddx+ddy*ddy) <= r*r;
        end
    end
endfunction
function in_circ;
    input [10:0] px,py,cx,cy,rs;
    reg [21:0] ddx,ddy;
    begin
        ddx = (px>cx)?(px-cx):(cx-px);
        ddy = (py>cy)?(py-cy):(cy-py);
        in_circ = (ddx*ddx+ddy*ddy) <= rs*rs;
    end
endfunction
wire btn1_hit = in_rrect(pixel_xpos,pixel_ypos,11'd69, 11'd165,11'd248,11'd305,11'd8);
wire btn2_hit = in_rrect(pixel_xpos,pixel_ypos,11'd310,11'd165,11'd489,11'd305,11'd8);
wire btn3_hit = in_rrect(pixel_xpos,pixel_ypos,11'd551,11'd165,11'd730,11'd305,11'd8);
wire calc_btn_hit = mode==2'd1 && in_rrect(pixel_xpos,pixel_ypos,11'd355,11'd70,11'd445,11'd140,11'd8);
wire track0_edge = mode==2'd1 && in_rrect(pixel_xpos,pixel_ypos,11'd159,11'd369,11'd641,11'd391,11'd11);
wire track0_fill = mode==2'd1 && in_rrect(pixel_xpos,pixel_ypos,11'd160,11'd370,11'd640,11'd390,11'd10);
wire knob0_edge  = mode==2'd1 && in_circ(pixel_xpos,pixel_ypos,knob0_x,knob0_y,11'd13);
wire knob0_fill  = mode==2'd1 && in_circ(pixel_xpos,pixel_ypos,knob0_x,knob0_y,11'd11);
wire track_edge = mode==2'd1 && in_rrect(pixel_xpos,pixel_ypos,11'd159,11'd423,11'd641,11'd445,11'd11);
wire track_fill = mode==2'd1 && in_rrect(pixel_xpos,pixel_ypos,11'd160,11'd424,11'd640,11'd444,11'd10);
wire knob_edge = in_circ(pixel_xpos,pixel_ypos,knob_x,knob_y,11'd13);
wire knob_fill = in_circ(pixel_xpos,pixel_ypos,knob_x,knob_y,11'd11);
wire track2_edge = mode==2'd2 && in_rrect(pixel_xpos,pixel_ypos,11'd159,11'd423,11'd641,11'd445,11'd11);
wire track2_fill = mode==2'd2 && in_rrect(pixel_xpos,pixel_ypos,11'd160,11'd424,11'd640,11'd444,11'd10);
wire knob2_edge  = mode==2'd2 && in_circ(pixel_xpos,pixel_ypos,knob2_x,knob2_y,11'd13);
wire knob2_fill  = mode==2'd2 && in_circ(pixel_xpos,pixel_ypos,knob2_x,knob2_y,11'd11);
wire in_b1t = pixel_xpos>=11'd95 && pixel_xpos<11'd223
           && pixel_ypos>=11'd219 && pixel_ypos<11'd251;
wire [1:0]  b1_ci = (pixel_xpos-11'd95)>>5;
wire [4:0]  b1_xi = pixel_xpos-11'd95-(b1_ci<<5);
wire [4:0]  b1_yi = pixel_ypos-11'd219;
wire        b1_pix = font32[b1_ci*32+b1_yi][31-b1_xi];
wire in_b2t = pixel_xpos>=11'd336 && pixel_xpos<11'd464
           && pixel_ypos>=11'd219 && pixel_ypos<11'd251;
wire [1:0]  b2_ci = (pixel_xpos-11'd336)>>5;
wire [4:0]  b2_xi = pixel_xpos-11'd336-(b2_ci<<5);
wire [4:0]  b2_yi = pixel_ypos-11'd219;
wire [3:0]  b2_char[0:3];
assign b2_char[0]=4'd4; assign b2_char[1]=4'd5; assign b2_char[2]=4'd6; assign b2_char[3]=4'd7;
wire        b2_pix = font32[b2_char[b2_ci]*32+b2_yi][31-b2_xi];
wire in_b3t = pixel_xpos>=11'd577 && pixel_xpos<11'd705
           && pixel_ypos>=11'd219 && pixel_ypos<11'd251;
wire [1:0]  b3_ci = (pixel_xpos-11'd577)>>5;
wire [4:0]  b3_xi = pixel_xpos-11'd577-(b3_ci<<5);
wire [4:0]  b3_yi = pixel_ypos-11'd219;
wire [3:0]  b3_char[0:3];
assign b3_char[0]=4'd4; assign b3_char[1]=4'd5; assign b3_char[2]=4'd8; assign b3_char[3]=4'd9;
wire        b3_pix = font32[b3_char[b3_ci]*32+b3_yi][31-b3_xi];
wire in_lbl = pixel_xpos>=11'd55 && pixel_xpos<11'd135
           && pixel_ypos>=11'd424 && pixel_ypos<11'd440;
wire [2:0]  lb_ci = (pixel_xpos-11'd55)>>4;
wire [3:0]  lb_xi = pixel_xpos-11'd55-(lb_ci<<4);
wire [3:0]  lb_yi = pixel_ypos-11'd424;
wire        lb_pix = font16[lb_ci*16+lb_yi][15-lb_xi];
wire in_d0 = pixel_xpos>=11'd657 && pixel_xpos<11'd665
          && pixel_ypos>=11'd424 && pixel_ypos<11'd440;
wire in_d1 = pixel_xpos>=11'd665 && pixel_xpos<11'd673
          && pixel_ypos>=11'd424 && pixel_ypos<11'd440;
wire [3:0]  d_yi = pixel_ypos-11'd424;
wire [2:0]  d0_xi = pixel_xpos-11'd657;
wire [2:0]  d1_xi = pixel_xpos-11'd665;
wire        d0_pix = (tens!=6'd0) && font8[tens*16+d_yi][7-d0_xi];
wire        d1_pix = font8[ones*16+d_yi][7-d1_xi];
wire [3:0] amp_w  = amp_pix / 10000;
wire [3:0] amp_th = (amp_pix / 1000) % 10;
wire [3:0] amp_h  = (amp_pix / 100) % 10;
wire [3:0] amp_t  = (amp_pix / 10) % 10;
wire [3:0] amp_o  = amp_pix % 10;
wire in_at_y = (mode==2'd1) && pixel_ypos>=11'd370 && pixel_ypos<11'd386;
wire in_at0 = in_at_y && pixel_xpos>=11'd55 && pixel_xpos<11'd63;
wire in_at1 = in_at_y && pixel_xpos>=11'd63 && pixel_xpos<11'd71;
wire in_at2 = in_at_y && pixel_xpos>=11'd79 && pixel_xpos<11'd87;
wire in_at3 = in_at_y && pixel_xpos>=11'd87 && pixel_xpos<11'd95;
wire in_at4 = in_at_y && pixel_xpos>=11'd95 && pixel_xpos<11'd103;
wire in_at5 = in_at_y && pixel_xpos>=11'd103 && pixel_xpos<11'd111;
wire [3:0] at_yi = pixel_ypos-11'd370;
wire [2:0] at0_xi = pixel_xpos-11'd55;
wire [2:0] at1_xi = pixel_xpos-11'd63;
wire [2:0] at2_xi = pixel_xpos-11'd79;
wire [2:0] at3_xi = pixel_xpos-11'd87;
wire [2:0] at4_xi = pixel_xpos-11'd95;
wire [2:0] at5_xi = pixel_xpos-11'd103;
wire at0_pix = (amp_w!=4'd0) && font8[amp_w*16+at_yi][7-at0_xi];
wire at1_pix = (amp_w!=4'd0 || amp_th!=4'd0) && font8[amp_th*16+at_yi][7-at1_xi];
wire at2_pix = (amp_w!=4'd0 || amp_th!=4'd0 || amp_h!=4'd0) && font8[amp_h*16+at_yi][7-at2_xi];
wire at3_pix = (amp_w!=4'd0 || amp_th!=4'd0 || amp_h!=4'd0 || amp_t!=4'd0) && font8[amp_t*16+at_yi][7-at3_xi];
wire at4_pix = font8[amp_o*16+at_yi][7-at4_xi];
wire at5_pix = 1'b0;
wire [3:0] sens_t = sens/10;
wire [3:0] sens_o = sens%10;
wire sens_d0 = mode==2'd2 && pixel_xpos>=11'd657 && pixel_xpos<11'd665
            && pixel_ypos>=11'd424 && pixel_ypos<11'd440;
wire sens_d1 = mode==2'd2 && pixel_xpos>=11'd665 && pixel_xpos<11'd673
            && pixel_ypos>=11'd424 && pixel_ypos<11'd440;
wire [3:0] s_yi = pixel_ypos-11'd424;
wire [2:0] s0_xi = pixel_xpos-11'd657;
wire [2:0] s1_xi = pixel_xpos-11'd665;
wire sd0_pix = (sens_t!=4'd0) && font8[sens_t*16+s_yi][7-s0_xi];
wire sd1_pix = font8[sens_o*16+s_yi][7-s1_xi];
wire [3:0] th_w  = thresh/10000;
wire [3:0] th_th = (thresh/1000)%10;
wire [3:0] th_h  = (thresh/100)%10;
wire [3:0] th_t  = (thresh/10)%10;
wire [3:0] th_o  = thresh%10;
wire th_d0 = mode==2'd1 && pixel_xpos>=11'd657 && pixel_xpos<11'd665
           && pixel_ypos>=11'd372 && pixel_ypos<11'd388;
wire th_d1 = mode==2'd1 && pixel_xpos>=11'd665 && pixel_xpos<11'd673
           && pixel_ypos>=11'd372 && pixel_ypos<11'd388;
wire th_d2 = mode==2'd1 && pixel_xpos>=11'd673 && pixel_xpos<11'd681
           && pixel_ypos>=11'd372 && pixel_ypos<11'd388;
wire th_d3 = mode==2'd1 && pixel_xpos>=11'd681 && pixel_xpos<11'd689
           && pixel_ypos>=11'd372 && pixel_ypos<11'd388;
wire th_d4 = mode==2'd1 && pixel_xpos>=11'd689 && pixel_xpos<11'd697
           && pixel_ypos>=11'd372 && pixel_ypos<11'd388;
wire [3:0] th_yi = pixel_ypos-11'd372;
wire [2:0] th0_xi = pixel_xpos-11'd657;
wire [2:0] th1_xi = pixel_xpos-11'd665;
wire [2:0] th2_xi = pixel_xpos-11'd673;
wire [2:0] th3_xi = pixel_xpos-11'd681;
wire [2:0] th4_xi = pixel_xpos-11'd689;
wire th0_pix = (th_w!=4'd0) && font8[th_w*16+th_yi][7-th0_xi];
wire th1_pix = (th_w!=4'd0 || th_th!=4'd0) && font8[th_th*16+th_yi][7-th1_xi];
wire th2_pix = (th_w!=4'd0 || th_th!=4'd0 || th_h!=4'd0) && font8[th_h*16+th_yi][7-th2_xi];
wire th3_pix = (th_w!=4'd0 || th_th!=4'd0 || th_h!=4'd0 || th_t!=4'd0) && font8[th_t*16+th_yi][7-th3_xi];
wire th4_pix = font8[th_o*16+th_yi][7-th4_xi];
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        pixel_data <= BG;
    end else begin

        if(btn1_hit) begin
            if(in_b1t && b1_pix) pixel_data <= BLACK;
            else pixel_data <= (mode==2'd0) ? BTN1_C : BTN1_G;
        end
        else if(btn2_hit) begin
            if(in_b2t && b2_pix) pixel_data <= BLACK;
            else pixel_data <= (mode==2'd1) ? BTN2_C : BTN2_G;
        end
        else if(btn3_hit) begin
            if(in_b3t && b3_pix) pixel_data <= BLACK;
            else pixel_data <= (mode==2'd2) ? BTN3_C : BTN3_G;
        end
        else if(calc_btn_hit) pixel_data <= calc_r ? 24'h808080 : 24'hFFFF00;

        else if(knob0_fill) pixel_data <= WHITE;
        else if(knob0_edge) pixel_data <= BLACK;
        else if(track0_edge && !track0_fill) pixel_data <= EDGE;
        else if(track0_fill) begin
            if(pixel_xpos <= knob0_x + 11'd11) pixel_data <= WHITE;
            else pixel_data <= GRAY;
        end

        else if(mode==2'd1 && knob_fill) pixel_data <= WHITE;
        else if(mode==2'd1 && knob_edge) pixel_data <= BLACK;
        else if(mode==2'd1 && track_edge && !track_fill) pixel_data <= EDGE;
        else if(mode==2'd1 && track_fill) begin
            if(pixel_xpos <= knob_x) pixel_data <= WHITE;
            else pixel_data <= GRAY;
        end
        else if(knob2_fill) pixel_data <= WHITE;
        else if(knob2_edge) pixel_data <= BLACK;
        else if(track2_edge && !track2_fill) pixel_data <= EDGE;
        else if(track2_fill) begin
            if(pixel_xpos <= knob2_x) pixel_data <= WHITE;
            else pixel_data <= GRAY;
        end
        else if(mode==2'd1 && in_lbl && lb_pix) pixel_data <= BLACK;
        else if(mode==2'd1 && in_d0 && d0_pix) pixel_data <= BLACK;
        else if(mode==2'd1 && in_d1 && d1_pix) pixel_data <= BLACK;
        else if(in_at0 && at0_pix) pixel_data <= BLACK;
        else if(in_at1 && at1_pix) pixel_data <= BLACK;
        else if(in_at2 && at2_pix) pixel_data <= BLACK;
        else if(in_at3 && at3_pix) pixel_data <= BLACK;
        else if(in_at4 && at4_pix) pixel_data <= BLACK;
        else if(in_at5 && at5_pix) pixel_data <= BLACK;
        else if(mode==2'd2 && sens_d0 && sd0_pix) pixel_data <= BLACK;
        else if(mode==2'd2 && sens_d1 && sd1_pix) pixel_data <= BLACK;
        else if(th_d0 && th0_pix) pixel_data <= BLACK;
        else if(th_d1 && th1_pix) pixel_data <= BLACK;
        else if(th_d2 && th2_pix) pixel_data <= BLACK;
        else if(th_d3 && th3_pix) pixel_data <= BLACK;
        else if(th_d4 && th4_pix) pixel_data <= BLACK;

        else pixel_data <= BG;
    end
end
endmodule
