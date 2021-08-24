Cond :: struct (code: Code) {}

cond :: ($code: Code) -> Cond(code) #expand {
    a : Cond(code) = ---;
    return a;
}

main :: () {
  cond(#code 0 < 10);
}
