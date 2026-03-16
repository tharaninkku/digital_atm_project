library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity database_register is
    Port (
        clk               : in  STD_LOGIC;
        reset             : in  STD_LOGIC;
        
        -- Inputs from Account Creation
        write_enable      : in  STD_LOGIC;                       
        account_in        : in  STD_LOGIC_VECTOR(15 downto 0);    
        password_in       : in  STD_LOGIC_VECTOR(15 downto 0);    
        
        -- Inputs from Transaction Modules (Math Units)
        update_bal_enable : in  STD_LOGIC;
        target_user_index : in  STD_LOGIC_VECTOR(1 downto 0);  
        new_balance_in    : in  STD_LOGIC_VECTOR(15 downto 0); 
        
        -- Outputs to the rest of the ATM
        all_accounts      : out STD_LOGIC_VECTOR(47 downto 0); 
        all_passwords     : out STD_LOGIC_VECTOR(47 downto 0);
        all_balances      : out STD_LOGIC_VECTOR(47 downto 0); 
        db_full           : out STD_LOGIC   
    );
end database_register;

architecture Behavioral of database_register is

    -- Create custom array types to hold 3 slots of 16-bit data
    type memory_array is array (0 to 2) of STD_LOGIC_VECTOR(15 downto 0);
    
    -- The actual storage vaults
    signal accounts_mem  : memory_array := (others => (others => '0'));
    signal passwords_mem : memory_array := (others => (others => '0'));
    signal balances_mem  : memory_array := (others => (others => '0'));
    
    -- Keeps track of how many users have registered (0, 1, 2, or 3)
    signal user_count : integer range 0 to 3 := 0;

begin

    -- 1. Synchronous Write Process (Saving Data)
    process(clk)
        variable target_idx : integer range 0 to 3;
    begin
        if rising_edge(clk) then
            if reset = '0' then
                -- WIPE THE VAULT
                accounts_mem  <= (others => (others => '0'));
                passwords_mem <= (others => (others => '0'));
                balances_mem  <= (others => (others => '0'));
                user_count    <= 0;
                
            else
                -- SCENARIO A: Saving a brand new user
                if write_enable = '1' then
                    if user_count < 3 then
                        accounts_mem(user_count)  <= account_in;
                        passwords_mem(user_count) <= password_in;
                        balances_mem(user_count)  <= x"1000"; -- Starting balance is exactly $0 (BCD)
                        user_count <= user_count + 1;
                    end if;
                
                -- SCENARIO B: Updating an existing user's balance
                elsif update_bal_enable = '1' then
                    -- Convert the 2-bit binary index into an integer so the array can read it
                    target_idx := to_integer(unsigned(target_user_index));
                    
                    -- Safety check to prevent crashing if index is somehow out of bounds
                    if target_idx < 3 then
                        balances_mem(target_idx) <= new_balance_in;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- 2. Asynchronous Read Process (Broadcasting Data)
    -- We pack the 3 separate 16-bit array slots into massive 48-bit cables.
    -- Slot 2 goes on the left (47 downto 32), Slot 1 in the middle (31 downto 16), Slot 0 on the right (15 downto 0)
    all_accounts  <= accounts_mem(2)  & accounts_mem(1)  & accounts_mem(0);
    all_passwords <= passwords_mem(2) & passwords_mem(1) & passwords_mem(0);
    all_balances  <= balances_mem(2)  & balances_mem(1)  & balances_mem(0);

    -- 3. Database Full Flag
    -- Tells the State Controller to lock the "Register" button if we hit 3 users
    db_full <= '1' when user_count = 3 else '0';

end Behavioral;