#import "Basic";

BIG_DATA :: Data.{ value = 1_000_000 };

Data :: struct {
    value: s32;
}

#run main();
main :: () {
    big_data : Data = BIG_DATA;

    if big_data == {
    case BIG_DATA;
        print("wow that's some big data.\n");
    case;
        assert(false);
    }
}
