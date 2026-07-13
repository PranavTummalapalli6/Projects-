async function hello() {
    return "Hello, World!";
}
const url = new URL("https://example.com");
let lucky = 23; //implicit
lucky = 23;
//let lucy; //inferred any type
let lucy = 23; //explicit
let font;
const p = {
    first: "John",
    last: "Doe"
};
const p2 = {
    first: "Usain",
    last: "Bolt",
    fast: true
};
//functions
function add(a, b) {
    return a + b;
}
function pow(x, y) {
    return Math.pow(x, y);
}
//arays
const arr = [1, 2, 3, 4, 5]; //number array
//generics
class observable {
    value;
    constructor(value) {
        this.value = value;
    }
}
let x = new observable(23);
let y;
export {};
