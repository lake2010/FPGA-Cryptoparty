--------------------------------------------------------------------------------
--                             ztex_wrapper.vhd
--    Overall wrapper for use with ZTEX 1.15y FPGA Bitcoin miners
--    Copyright (C) 2016  Jarrett Rainier
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.sha1_pkg.all;


entity ztex_wrapper is
    port(
        rst_i         : in std_logic;   --RESET
        cs_i          : in std_logic;   --CS
        cont_i        : in std_logic;   --CONT
        clk_i         : in std_logic;   --IFCLK

        dat_i         : in unsigned(0 to 7);  --FD
        dat_o         : out std_ulogic_vector(0 to 7);  --pc

        SLOE          : out std_logic;  --SLOE
        SLRD          : out std_logic;  --SLRD
        SLWR          : out std_logic;  --SLWR
        FIFOADR0      : out std_logic;  --FIFOADR0
        FIFOADR1      : out std_logic;  --FIFOADR1
        PKTEND        : out std_logic;  --PKTEND
   
        FLAGA         : in std_logic;   --FLAGA   EP2 FIFO Empty flag (FLAGA)
        FLAGB         : in std_logic    --FLAGB
    );
end ztex_wrapper;

architecture RTL of ztex_wrapper is
    component wpa2_main
    port(
        clk_i           : in    std_ulogic;
        rst_i           : in    std_ulogic;
        cont_i          : in    std_ulogic;
        ssid_dat_i      : in    ssid_data;
        data_dat_i      : in    packet_data;
        anonce_dat      : in    nonce_data;
        cnonce_dat      : in    nonce_data;
        amac_dat        : in    mac_data;
        cmac_dat        : in    mac_data;
        mk_initial      : in   mk_data;
        mk_end          : in   mk_data;
        mk_dat_o        : out   mk_data;
        mk_valid_o      : out   std_ulogic;
        wpa2_complete_o : out   std_ulogic
    );
    end component;
   
	type state_type is (STATE_IDLE, STATE_PACKET, STATE_START, STATE_END, STATE_PROCESS, STATE_OUT);
    
	signal state           : state_type := STATE_IDLE;
   
    --Inputs
    signal handshake_dat   : handshake_data;
    signal mk_initial      : mk_data;
    signal mk_end          : mk_data;
    
    --Input split
    signal ssid_dat        : ssid_data;
    signal data_dat        : packet_data;
    signal datalength_dat  : integer range 0 to 255;
    signal anonce_dat      : nonce_data;
    signal cnonce_dat      : nonce_data;
    signal amac_dat        : mac_data;
    signal cmac_dat        : mac_data;
    signal mic_dat         : mic_data;
    
    
    --signal ssid_len      : integer range 0 to 63;
    --signal mk_len        : integer range 0 to 63;
    constant mk_len        : integer := 10;
    
    --Outputs
    signal mk_dat          : mk_data;
        
    signal wpa2_complete   : std_ulogic := '0';
    signal pmk_valid       : std_ulogic := '0';
    
    --Internal
    signal i               : integer range 0 to 391;
    signal i_word          : integer range 0 to 3;
    signal i_mux           : integer range 0 to 1;

    -- synthesis translate_off
    signal test_ssid_1: unsigned(0 to 7);
    signal test_ssid_2: unsigned(0 to 7);
    signal test_ssid_3: unsigned(0 to 7);
    
    signal test_mac_1: unsigned(0 to 7);
    signal test_mac_2: unsigned(0 to 7);
    signal test_mac_3: unsigned(0 to 7);
    
    signal test_nonce_1: unsigned(0 to 7);
    signal test_nonce_2: unsigned(0 to 7);
    signal test_nonce_3: unsigned(0 to 7);
    
    signal test_keymic_1: unsigned(0 to 7);
    signal test_keymic_2: unsigned(0 to 7);
    signal test_keymic_3: unsigned(0 to 7);
    
    signal test_mk1: unsigned(0 to 7);
    signal test_mk2: unsigned(0 to 7);
    signal test_mk3: unsigned(0 to 7);
    
    signal test_byte_1: unsigned(0 to 7);
    signal test_byte_2: std_ulogic_vector(0 to 7);
    signal test_byte_3: std_ulogic_vector(0 to 7);
    signal test_byte_4: std_ulogic_vector(0 to 7);
    signal test_byte_5: std_ulogic_vector(0 to 7);
    
    signal test_state: integer range 0 to 6;
    -- synthesis translate_on
    
begin

    MAIN1: wpa2_main port map (clk_i,rst_i,cont_i,
            ssid_dat,data_dat,anonce_dat,cnonce_dat,amac_dat,cmac_dat,
            mk_initial,mk_end,
            mk_dat,pmk_valid,wpa2_complete);
    
    SLOE <= '1'     when cs_i = '1' else 'Z';
    SLRD <= '1'     when cs_i = '1' else 'Z';
    SLWR <= '0'  when cs_i = '1' else 'Z';
    FIFOADR0 <= '0' when cs_i = '1' else 'Z';
    FIFOADR1 <= '0' when cs_i = '1' else 'Z';
    PKTEND <= '1'   when cs_i = '1' else 'Z';		-- no data alignment
    --FD <= FD_R      when cs_i = '1' else (others => 'Z');
    
    process(clk_i, rst_i)   
    begin
        if rst_i = '1' then
            --GEN_CNT <= ( others => '0' );
            --INT_CNT <= ( others => '0' );
            --FIFO_WORD <= '0';
            --SLWR_R <= '1';
            
            --latch_input <= "00";
            state <= STATE_IDLE;
            
            i <= 0;
            i_word <= 0;
            i_mux <= 0;
            
        elsif (clk_i'event and clk_i = '1') then
            if state = STATE_IDLE then
                state <= STATE_PACKET;
                
                i <= 0;
                
            elsif state = STATE_PACKET then
                handshake_dat(i) <= dat_i;
                
                if i = 391 then
                    state <= STATE_START;
                    i <= 0;
                else
                    i <= i + 1;
                end if;
                
            elsif state = STATE_START then
                mk_initial(i) <= dat_i;
                
                if i = mk_len - 1 then
                    state <= STATE_END;
                    i <= 0;
                else
                    i <= i + 1;
                end if;
                
            elsif state = STATE_END then
                mk_end(i) <= dat_i;
                
                if i = mk_len - 1 then
                    state <= STATE_PROCESS;
                    i <= 0;
                else
                    i <= i + 1;
                end if;
                
            elsif state = STATE_PROCESS and wpa2_complete = '1' then
                    state <= STATE_OUT;
                    --Testing only, this will fail past 391 attempts
                    i <= 0;
            elsif state = STATE_PROCESS then
                    --Testing only, this will fail past 391 attempts
                    i <= i + 1;
            end if;
        end if;
    end process;

    ssid_dat <= ssid_data(handshake_dat(0 to 35));      --36
    amac_dat <= mac_data(handshake_dat(36 to 41));      --6
    cmac_dat <= mac_data(handshake_dat(42 to 47));      --6
    anonce_dat <= nonce_data(handshake_dat(48 to 79));    --32
    cnonce_dat <= nonce_data(handshake_dat(80 to 111));    --32
    data_dat <= packet_data(handshake_dat(112 to 367));      --256
    --datalength_dat <= to_integer(unsigned(handshake_dat(368 to 371)));--4
    mic_dat <= mic_data(handshake_dat(376 to 391));       --16
    
	--write_o <= std_logic_vector( pb_buf ) when select_i = '1' else (others => 'Z');
    -- synthesis translate_off
    test_byte_1 <= handshake_dat(3);
    
    test_ssid_1 <= ssid_dat(0);
    test_ssid_2 <= ssid_dat(3);
    test_ssid_3 <= ssid_dat(6);
    
    test_mac_1 <= amac_dat(0);
    test_mac_2 <= amac_dat(3);
    test_mac_3 <= cmac_dat(5);
    
    test_nonce_1 <= anonce_dat(0);
    test_nonce_2 <= anonce_dat(3);
    test_nonce_3 <= cnonce_dat(6);
    
    test_keymic_1 <= mic_dat(0);
    test_keymic_2 <= mic_dat(14);
    test_keymic_3 <= mic_dat(15);
    
    test_mk1 <= mk_initial(0);
    test_mk2 <= mk_end(7);
    test_mk3 <= mk_end(9);
    
    with state select
        test_state <= 0 when STATE_IDLE,
            1 when STATE_PACKET,
            2 when STATE_START,
            3 when STATE_END,
            4 when STATE_PROCESS,
            5 when STATE_OUT,
            6 when others;
    -- synthesis translate_on

    
end RTL; 