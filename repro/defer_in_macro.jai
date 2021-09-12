#import "Basic";

macro_with_ticked_defer :: (condition: bool) #expand {
    if condition        return;
    `defer {
        assert(!condition);
    }
}

macro_with_defer :: (condition: bool) #expand {
    if condition        return;
    defer {
        assert(!condition);
    }
}

proc_with_defer :: (condition: bool) {
    if condition        return;
    defer {
        assert(!condition);
    }
}

main :: () {
    {
        proc_with_defer(false);
    }

    {
        macro_with_defer(false);
    }

    {
        macro_with_ticked_defer(false);
    }

    {
        proc_with_defer(true);
    }

    {
        macro_with_defer(true);
    }

    { // this one crashes
        macro_with_ticked_defer(true);
    }
}

#run main();
