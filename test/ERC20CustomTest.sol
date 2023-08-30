pragma solidity 0.8.19;
import "../contracts/ERC20Burn.sol";
import "./helper.sol";


/// @notice Run with medusa fuzz --target test/ERC20CustomTest.sol --deployment-order ExternalTest

contract Token is ERC20Burn, PropertiesAsserts {
    bool _init_switch; // False by default
    address alice;
    address externalTester;
    address medusa;

    /// @notice Function Signatures
    /// @dev These are used to identify call origins and perform appropriate invariant checks
    bytes4 private testTransferFromSig = bytes4(keccak256("testTransferFrom(uint)"));
    bytes4 private testTransferSig = bytes4(keccak256("testTransfer(address,uint256)"));
    bytes4 private testBurnSig = bytes4(keccak256("testBurn(uint256)"));
    bytes4 private testMintSig = bytes4(keccak256("testMint(address,uint256)"));
    bytes4 private testApproveSig = bytes4(keccak256("testApprove(address,uint256)"));

    /// @notice Initialization Function
    /// @dev
    /// 1. Callable once
    /// 2. Sets some initial chain state (e.g balances)
    function _init(address _alice, address _externalTester, address _medusa, uint256 userAmount, uint256 contractAmount) external {
        require(_init_switch == false);
        _init_switch = true;

        // Store testing addresses
        alice = _alice;
        externalTester = _externalTester;
        medusa = _medusa;

        // Init contract state
        _mint(alice, userAmount);               // 100
        _mint(externalTester, userAmount);      // 100
        _mint(medusa, userAmount);              // 100
        _mint(address(this), contractAmount);   // 1000
    }

    /*//////////////////////////////////////////////////////////////
                        REUSABLE INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice checkSupply() is used to check the totalSupply is correctly maintained
    /// @dev Assumptions:
    /// 1. totalSupply is increased by X when X amount is minted
    /// 2. totalSupply is decreased by X when X amount is burned
    /// 3. totalSupply is never altered anywhere else in the code-base
    modifier checkSupply(uint256 amount) {
        uint256 supplyBefore = totalSupply;
        _;

        if (msg.sig == testBurnSig) {
            /// @notice totalSupply should decrease when burn()
            assertEq(totalSupply, supplyBefore - amount, "Supply not decremented after Burn()");

        } else if (msg.sig == testMintSig) {
            /// @notice totalSupply should increase when mint()
            assertEq(totalSupply, supplyBefore + amount, "Supply not incremented after Mint()");

        } else {
            /// @notice totalSupply should not change through other operations
            assertEq(supplyBefore, totalSupply, "Total supply invariant altered");
        }
    }

    /// @notice This is used to ensure balance is handled safely
    /// @dev Assumptions:
    /// 1. transfer() should increment the recipient balance by X
    /// 2. transfer() should decrement the senders balance by X
    function balanceUpdateCheck(
        address from,
        address to,
        uint256 balBefore_from,
        uint256 balBefore_to) public {

        /// @notice Only callable from transfer() or transferFrom() checks
        require(
            msg.sig == testTransferSig ||
            msg.sig == testTransferFromSig,
            "Invalid function signature"
        );

        /// @notice Check the increment value and decrement value are equal
        assertEq(
            balanceOf[to] - balBefore_to, // Balance increment value
            balBefore_from - balanceOf[from], // Balance decrement value
            "(Transfer) Balance is not incremented/decremented uniformly"
        );
    }

    /// @notice This is used to clamp the transfer amount within a certain range
    /// @dev Assumptions:
    /// 1. Amount should be less than or equal to allowance (transferFrom)
    /// 2. Amount should be less than or equal to balanceOf (transfer & transferFrom)
    function clampAmount(address from, address to, uint256 amount) public returns(uint256) {

        require(
            msg.sig == testTransferSig ||
            msg.sig == testTransferFromSig,
            "Invalid function signature"
        );

        if(msg.sig == testTransferFromSig) {
            amount = clampLte(amount, balanceOf[from]); // Clamp amount > balance
            amount = clampLte(amount, allowance[from][msg.sender]); // Clamp amount > allowance
        } else {
            amount = clampLte(amount, balanceOf[from]); // Clamp amount > balance
        }

        return amount;
    }

    /*//////////////////////////////////////////////////////////////
                    TEST EXECUTION & SYSTEM ENTRY POINTS
    //////////////////////////////////////////////////////////////*/

    /// @notice This is used to ensure balance is handled safely
    /// @dev Assumptions:
    /// 1. Conditions of balanceUpdateCheck()
    /// 2. Inputs can be bounded by clampAmount()
    function testTransfer(address to, uint256 amount) public checkSupply(amount) {
        amount = clampAmount(msg.sender, to, amount);

        uint256 balBefore_to = balanceOf[to];
        uint256 balBefore_from = balanceOf[msg.sender];

        // Perform transfer
        transfer(to, amount);

        // Check transfer
        balanceUpdateCheck(msg.sender, to, balBefore_from, balBefore_to);
    }

    /// @notice This test ensures that allowance is correctly incremented/decremented
    /// @dev Assumptions:
    /// 1. Spender's allowance should equal X
    function testApprove(address spender, uint256 amount) public {
        uint256 balanceOfParties = balanceOf[address(this)] + balanceOf[spender] + balanceOf[msg.sender];

        approve(spender, amount);
        assertEq(amount, allowance[msg.sender][spender], "Allowance not updated correctly");
        
    }

    /// @notice This test ensures that tokens are actually burned
    /// @dev Assumptions:
    /// 1. When totalSupply is decreased by X caller balance is decreased by X
    function testBurn(uint256 amount) public checkSupply(amount) {
        uint256 balBefore_from = balanceOf[msg.sender];
        _burn(msg.sender, amount);
        assertEq(balBefore_from, balanceOf[msg.sender] + amount, "Balance not decremented");
    }

    /// @notice This test ensures that tokens are actually minted
    /// @dev Assumptions:
    /// 1. When totalSupply is increased by X caller balance is increased by X
    function testMint(address to, uint256 amount) public checkSupply(amount) {
        /// @notice Set mint capacity to not explode state in testing
        require(balanceOf[to] + amount <= balanceOf[address(this)]);
        
        uint256 balBefore_to = balanceOf[to]; 
        _mint(to, amount);
        assertEq(balBefore_to, balanceOf[to] - amount, "Balance not incremented");
    }
}

/*//////////////////////////////////////////////////////////////
                    FOR EXTNERAL TESTING
//////////////////////////////////////////////////////////////*/

contract ExternalTest is PropertiesAsserts {
    Token token;
    User alice;

    constructor() {
        token = new Token();
        alice = new User(token, address(this));

        // Init token supply
        uint256 userAmount = 100000;
        uint256 contractAmount = 10000000;
        token._init(address(alice), address(this), msg.sender, userAmount, contractAmount);
    }

    /// @notice This is used to ensure balance is handled safely
    /// @dev Assumptions
    /// 1. Amount X should not exceed Allowance
    /// 2. Conditions of balanceUpdateCheck()
    /// 4. Allowance should be decreased by amount X
    /// 6. Allowance should not be decreased by amount X if previously set to type(uint256).max
    /// 5. Inputs can be bounded by clampAmount()
    function testTransferFrom(uint amount, address to) public {
        // Get balances before
        uint balBefore_from = token.balanceOf(address(alice));
        uint balBefore_to = token.balanceOf(to);

        // Get approval before
        uint approvedAmount = token.allowance(
            address(alice), // From parameter (Alice User)
            address(this)   // Spender parameter (External Tester e.g This address)
        );

        // Clamp amount to Alice's balance and Tester's allowance
        amount = token.clampAmount(address(alice), to, amount);

        // Perform transferFrom()
        token.transferFrom(address(alice), to, amount);

        // Check allowance satisfies amount
        assertLte(amount, approvedAmount, "Amount Exceeded Allowance");

        uint256 allowanceAfter = token.allowance(address(alice), address(this));

        // Check allowance is updated correctly
        // Allowances == type(uint256).max are not updated
        if (approvedAmount != type(uint256).max) {
            assertEq(allowanceAfter, approvedAmount - amount, "Allowance not decreased");
        } else {
            assertEq(allowanceAfter, approvedAmount, "Allowance was decreased - despite being equal to type(uint256).max");
        }

        // Check transfer
        token.balanceUpdateCheck(
            address(alice), // From parameter (Alice User)
            to,
            balBefore_from,
            balBefore_to
        );

    }
}

contract User {
    Token token;
    address immutable externalTester;

    constructor(Token _token, address _externalTester) {
        token = _token;
        externalTester = _externalTester;
    }

    function approve(uint256 amount) public {
        token.testApprove(externalTester, amount);
    }

    function transfer(address to, uint amount) public {
        token.testTransfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public {
        token.transferFrom(from, to, amount);
    }
}