library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity login is
    Port (
        clk                  : in  STD_LOGIC;
        reset                : in  STD_LOGIC;
        enable               : in  STD_LOGIC;
        sw_input             : in  STD_LOGIC_VECTOR (15 downto 0);
        btn_enter            : in  STD_LOGIC;
        all_accounts         : in  STD_LOGIC_VECTOR (47 downto 0); -- 3 accounts x 16 bits
        all_passwords        : in  STD_LOGIC_VECTOR (47 downto 0); -- 3 passwords x 16 bits
        seg_output           : out STD_LOGIC_VECTOR (6 downto 0);
        digit_select         : out STD_LOGIC_VECTOR (7 downto 0);
        login_success        : out STD_LOGIC;
        logged_in_user_index : out STD_LOGIC_VECTOR (1 downto 0)
    );
end login;

architecture Behavioral of login is

    -- FSM States
    type state_type is (IDLE, ENTER_ACCOUNT, ENTER_PASSWORD, VERIFY, DONE);
    signal state : state_type := IDLE;
    
    -- Temporary storage for what the user types
    signal temp_acc : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    signal temp_pwd : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    
    -- Debounce signals
    signal btn_reg    : std_logic_vector(1 downto 0) := "00";
    signal btn_stable : std_logic := '0';
    signal btn_prev   : std_logic := '0';
    signal db_count   : integer range 0 to 1000000 := 0; 

    -- Display signals
    signal refresh_cnt : unsigned(19 downto 0) := (others => '0');
    signal active_val  : std_logic_vector(3 downto 0);

begin

    -- 1. Button Debouncer
    process(clk) begin
        if rising_edge(clk) then
            btn_reg <= btn_reg(0) & btn_enter;
            if (btn_reg(1) /= btn_reg(0)) then
                db_count <= 0;
            elsif (db_count < 1000000) then
                db_count <= db_count + 1;
            else
                btn_stable <= btn_reg(1); 
            end if;
        end if;
    end process;

    -- 2. Display Refresh Counter
    process(clk) begin
        if rising_edge(clk) then refresh_cnt <= refresh_cnt + 1; end if;
    end process;

    -- 3. 7-Segment Multiplexer
    process(refresh_cnt, state, sw_input)
    begin
        digit_select <= (others => '1'); 
        active_val <= "1111"; 

        if state /= IDLE then
            case refresh_cnt(19 downto 17) is
                -- Show what the user is typing on the right 4 digits
                when "000" => digit_select(0) <= '0'; active_val <= sw_input(3 downto 0);
                when "001" => digit_select(1) <= '0'; active_val <= sw_input(7 downto 4);
                when "010" => digit_select(2) <= '0'; active_val <= sw_input(11 downto 8);
                when "011" => digit_select(3) <= '0'; active_val <= sw_input(15 downto 12);
                
                -- Turn off the left 4 digits
                when "100" => digit_select(4) <= '0'; active_val <= "1111"; 
                when "101" => digit_select(5) <= '0'; active_val <= "1111"; 
                when "110" => digit_select(6) <= '0'; active_val <= "1111"; 
                when "111" => digit_select(7) <= '0'; active_val <= "1111"; 
                when others => null;
            end case;
        end if;
    end process;

    -- 4. BCD Decoder
    process(active_val) begin
        case active_val is
            when "0000" => seg_output <= "1000000"; -- 0
            when "0001" => seg_output <= "1111001"; -- 1
            when "0010" => seg_output <= "0100100"; -- 2
            when "0011" => seg_output <= "0110000"; -- 3
            when "0100" => seg_output <= "0011001"; -- 4
            when "0101" => seg_output <= "0010010"; -- 5
            when "0110" => seg_output <= "0000010"; -- 6
            when "0111" => seg_output <= "1111000"; -- 7
            when "1000" => seg_output <= "0000000"; -- 8
            when "1001" => seg_output <= "0010000"; -- 9
            when others => seg_output <= "1111111"; -- Blank
        end case;
    end process;

    -- 5. Main FSM (The Brain)
    process(clk) begin
        if rising_edge(clk) then
            if reset = '0' or enable = '0' then 
                state <= IDLE; 
                login_success <= '0';
                logged_in_user_index <= "00";
                temp_acc <= (others => '0');
                temp_pwd <= (others => '0');
                btn_prev <= '0';
            else
                btn_prev <= btn_stable; 
                
                if (btn_stable = '1' and btn_prev = '0') then
                    case state is
                        when IDLE => 
                            state <= ENTER_ACCOUNT;
                        
                        when ENTER_ACCOUNT =>
                            temp_acc <= sw_input;
                            state <= ENTER_PASSWORD;
                            
                        when ENTER_PASSWORD =>
                            temp_pwd <= sw_input;
                            state <= VERIFY;
                            
                        when VERIFY =>
                            -- Check User 0
                            if (temp_acc = all_accounts(15 downto 0)) and (temp_pwd = all_passwords(15 downto 0)) then
                                logged_in_user_index <= "00";
                                login_success <= '1';
                                state <= DONE;
                                
                            -- Check User 1
                            elsif (temp_acc = all_accounts(31 downto 16)) and (temp_pwd = all_passwords(31 downto 16)) then
                                logged_in_user_index <= "01";
                                login_success <= '1';
                                state <= DONE;
                                
                            -- Check User 2
                            elsif (temp_acc = all_accounts(47 downto 32)) and (temp_pwd = all_passwords(47 downto 32)) then
                                logged_in_user_index <= "10";
                                login_success <= '1';
                                state <= DONE;
                                
                            -- Login Failed (Wrong account or password)
                            else
                                state <= ENTER_ACCOUNT; -- Kick them back to the start
                            end if;
                            
                        when DONE =>
                            -- Stay here. The top module will see login_success = '1' and drop our 'enable' to '0'.
                            null;
                            
                    end case;
                end if;
            end if;
        end if;
    end process;

end Behavioral;