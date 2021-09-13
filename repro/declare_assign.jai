#import "Basic";

returns_two_values :: () -> bool, u64 {
    return true, 12;
}

#run main();
main :: () {

    success := false;
    success, value := returns_two_values();

    assert(success);
}
