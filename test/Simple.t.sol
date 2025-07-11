// Basic test
import "forge-std/Test.sol";
contract SimpleTest is Test {
    function testBasic() public {
        assertEq(1+1, 2);
    }
}
