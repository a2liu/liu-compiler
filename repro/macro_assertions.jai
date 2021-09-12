#import "Basic";

asserting_macro :: () #expand {
    assert(false);
}

interim_macro :: () #expand {
    asserting_macro();
}

normal_procedure :: () {
    interim_macro();
}

#run main();
main :: () {
    normal_procedure();
}
