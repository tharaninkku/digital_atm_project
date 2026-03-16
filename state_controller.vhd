library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity state_controller is
    Port ( 
        clk                   : in STD_LOGIC;
        reset                 : in STD_LOGIC;
        
        -- Physical Navigation Buttons
        btn_left              : in STD_LOGIC;
        btn_right             : in STD_LOGIC;
        btn_top               : in STD_LOGIC;
        btn_bottom            : in STD_LOGIC;
        btn_center            : in STD_LOGIC;
        
        -- Status signals FROM your modules
        create_acc_done       : in STD_LOGIC;
        login_success         : in STD_LOGIC;
        db_full               : in STD_LOGIC;
        
        -- Status signals FROM Mew & Kawin's modules
        deposit_done          : in STD_LOGIC; 
        withdraw_done         : in STD_LOGIC;
        transfer_done         : in STD_LOGIC;
        
        -- Math Error Flags
        adder_overflow        : in STD_LOGIC;
        sub_underflow         : in STD_LOGIC;
        
        -- Outputs TO control the ATM
        update_balance_enable : out STD_LOGIC;                       
        current_state         : out STD_LOGIC_VECTOR (2 downto 0)
    );
end state_controller;

architecture Behavioral of state_controller is

    -- Define the states matching the top_module multiplexers
    constant S_START    : STD_LOGIC_VECTOR(2 downto 0) := "000";
    constant S_REG      : STD_LOGIC_VECTOR(2 downto 0) := "001";
    constant S_LOGIN    : STD_LOGIC_VECTOR(2 downto 0) := "010";
    constant S_MENU     : STD_LOGIC_VECTOR(2 downto 0) := "011";
    constant S_DEPOSIT  : STD_LOGIC_VECTOR(2 downto 0) := "100";
    constant S_WITHDRAW : STD_LOGIC_VECTOR(2 downto 0) := "101";
    constant S_TRANSFER : STD_LOGIC_VECTOR(2 downto 0) := "110";
    
    -- We add a brief state just to trigger the database save
    constant S_UPDATE   : STD_LOGIC_VECTOR(2 downto 0) := "111";

    signal state, next_state : STD_LOGIC_VECTOR(2 downto 0) := S_START;
    
    -- Button edge detection (to prevent holding a button from skipping menus)
    signal btn_reg : std_logic_vector(4 downto 0); -- Top, Bottom, Left, Right, Center
    signal btn_prev : std_logic_vector(4 downto 0);

begin

    -- 1. State Register & Edge Detection
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '0' then
                state <= S_START;
                btn_prev <= (others => '0');
            else
                state <= next_state;
                
                -- Capture button states to detect "fresh presses" in the logic below
                btn_prev(0) <= btn_top;
                btn_prev(1) <= btn_bottom;
                btn_prev(2) <= btn_left;
                btn_prev(3) <= btn_right;
                btn_prev(4) <= btn_center;
            end if;
        end if;
    end process;

    -- 2. Next State Logic (The Traffic Cop)
    process(state, btn_top, btn_bottom, btn_left, btn_right, btn_center, btn_prev, 
            create_acc_done, login_success, db_full, deposit_done, withdraw_done, transfer_done, sub_underflow)
    begin
        -- Default: stay in the current state
        next_state <= state;
        
        case state is
            when S_START =>
                -- START SCREEN: Left = Register, Right = Login
                if (btn_left = '1' and btn_prev(2) = '0') then
                    -- Only allow registration if the database isn't full!
                    if db_full = '0' then 
                        next_state <= S_REG;
                    end if;
                elsif (btn_right = '1' and btn_prev(3) = '0') then
                    next_state <= S_LOGIN;
                end if;

            when S_REG =>
                -- Waits here until your Account Creation chip shouts "DONE"
                if create_acc_done = '1' then
                    next_state <= S_START; -- Send back to start to log in
                end if;

            when S_LOGIN =>
                -- Waits here until your Login chip shouts "SUCCESS"
                if login_success = '1' then
                    next_state <= S_MENU;
                end if;

            when S_MENU =>
                -- MAIN MENU: Top = Deposit, Bottom = Withdraw, Center = Transfer
                -- (You can change these button mappings to whatever your group prefers)
                if (btn_top = '1' and btn_prev(0) = '0') then
                    next_state <= S_DEPOSIT;
                elsif (btn_bottom = '1' and btn_prev(1) = '0') then
                    next_state <= S_WITHDRAW;
                elsif (btn_center = '1' and btn_prev(4) = '0') then
                    next_state <= S_TRANSFER;
                end if;

            when S_DEPOSIT =>
                if deposit_done = '1' then
                    next_state <= S_UPDATE; -- Go to save the new balance
                end if;

            when S_WITHDRAW =>
                if withdraw_done = '1' then
                    -- Only save if they didn't try to withdraw more than they have!
                    if sub_underflow = '0' then
                        next_state <= S_UPDATE;
                    else
                        next_state <= S_MENU; -- Error, go back to menu
                    end if;
                end if;

            when S_TRANSFER =>
                if transfer_done = '1' then
                    if sub_underflow = '0' then
                        next_state <= S_UPDATE;
                    else
                        next_state <= S_MENU;
                    end if;
                end if;
                
            when S_UPDATE =>
                -- This state lasts exactly 1 clock cycle to pulse the update_balance_enable wire
                next_state <= S_MENU;

            when others =>
                next_state <= S_START;
        end case;
    end process;

    -- 3. Output Logic
    -- Send the state down the wire so the top_module multiplexer knows which chip to turn on
    current_state <= state;
    
    -- Fire the save signal to the database ONLY when we are in the brief UPDATE state
    update_balance_enable <= '1' when state = S_UPDATE else '0';

end Behavioral;