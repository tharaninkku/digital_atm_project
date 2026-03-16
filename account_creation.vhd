library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity account_creation is
    Port (
        clk           : in  STD_LOGIC;
        reset         : in  STD_LOGIC;
        enable        : in  STD_LOGIC; -- NEW: Chip only works when FSM enables it
        sw_input      : in  STD_LOGIC_VECTOR (15 downto 0);
        btn_enter     : in  STD_LOGIC;
        state_led     : out STD_LOGIC_VECTOR (1 downto 0);
        seg_output    : out STD_LOGIC_VECTOR (6 downto 0);
        digit_select  : out STD_LOGIC_VECTOR (7 downto 0);
        create_done   : out STD_LOGIC;                       -- NEW: Tells FSM we are finished
        account_out   : out STD_LOGIC_VECTOR (15 downto 0);  -- NEW: Sends assigned account ID to DB
        password_out  : out STD_LOGIC_VECTOR (15 downto 0)   -- NEW: Sends verified password to DB
    );
end account_creation;

architecture Behavioral of account_creation is
    type state_type is (IDLE, SET_PASSWORD, CONFIRM_PASSWORD, DONE);
    signal state : state_type := IDLE;
    
    -- We keep acc_count to auto-assign an account ID (0, 1, 2) to the new user
    signal acc_count : unsigned(3 downto 0) := (others => '0');
    signal pwd_1     : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    
    -- Debounce signals
    signal btn_reg      : std_logic_vector(1 downto 0) := "00";
    signal btn_stable   : std_logic := '0';
    signal btn_prev     : std_logic := '0';
    signal db_count     : integer range 0 to 1000000 := 0; 

    signal refresh_cnt  : unsigned(19 downto 0) := (others => '0');
    signal active_val   : std_logic_vector(3 downto 0);

begin
    -- 1. Debounce Process 
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

    -- 2. Refresh Counter (Multiplexing)
    process(clk) begin
        if rising_edge(clk) then refresh_cnt <= refresh_cnt + 1; end if;
    end process;

    -- 3. Display Logic (8 Digits)
    process(refresh_cnt, acc_count, pwd_1, state, sw_input)
    begin
        digit_select <= (others => '1'); 
        active_val <= "1111"; 

        if state /= IDLE then
            case refresh_cnt(19 downto 17) is
                -- Right 4 digits show the current switches (what the user is typing)
                when "000" => digit_select(0) <= '0'; active_val <= sw_input(3 downto 0);
                when "001" => digit_select(1) <= '0'; active_val <= sw_input(7 downto 4);
                when "010" => digit_select(2) <= '0'; active_val <= sw_input(11 downto 8);
                when "011" => digit_select(3) <= '0'; active_val <= sw_input(15 downto 12);

                -- Left 4 digits show the Account ID being created
                when "100" => digit_select(4) <= '0'; active_val <= std_logic_vector(acc_count);
                when "101" => digit_select(5) <= '0'; active_val <= "0000"; 
                when "110" => digit_select(6) <= '0'; active_val <= "0000"; 
                when "111" => digit_select(7) <= '0'; active_val <= "0000"; 
                when others => null;
            end case;
        end if;
    end process;

    -- 4. Decoder
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
            when others => seg_output <= "1111111"; -- Blank for A-F since this is BCD
        end case;
    end process;

    -- 5. Main FSM 
    process(clk) begin
        if rising_edge(clk) then
            -- If reset is pressed OR the top module disables this chip, go to sleep
            if reset = '0' or enable = '0' then 
                state <= IDLE; 
                create_done <= '0';
                account_out <= (others => '0');
                password_out <= (others => '0');
                btn_prev <= '0';
            else
                btn_prev <= btn_stable; 
                
                -- Detect a fresh button press
                if (btn_stable = '1' and btn_prev = '0') then
                    case state is
                        when IDLE => 
                            -- Once enabled, pressing enter starts the process
                            state <= SET_PASSWORD;
                        
                        when SET_PASSWORD =>
                            pwd_1 <= sw_input;
                            state <= CONFIRM_PASSWORD;
                        
                        when CONFIRM_PASSWORD =>
                            if sw_input = pwd_1 then
                                -- Success! Output the data to the DB wires
                                password_out <= pwd_1;
                                
                                -- Pad the 4-bit acc_count to 16 bits for the output
                                account_out <= std_logic_vector(resize(acc_count, 16));
                                
                                -- Tell the top module we are finished
                                create_done <= '1'; 
                                state <= DONE;
                            else
                                -- Passwords didn't match, try again
                                state <= SET_PASSWORD; 
                            end if;
                        
                        when DONE => 
                            -- Only increment if we haven't hit the 3-user limit (0, 1, 2)
                            if acc_count < 2 then
                                acc_count <= acc_count + 1;
                            end if;
                            
                            -- We stay in DONE. The FSM will see create_done = '1', 
                            -- transition to LOGIN state, and drop our enable signal to '0',
                            -- which will force us back to IDLE.
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- 6. Status LEDs
    process(state) begin
        case state is
            when SET_PASSWORD     => state_led <= "01";
            when CONFIRM_PASSWORD => state_led <= "10";
            when DONE             => state_led <= "11";
            when others           => state_led <= "00";
        end case;
    end process;

end Behavioral;