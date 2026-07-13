import * as _ from "lodash";

async function hello() {
    return "Hello, World!";
}   

const url = new URL("https://example.com");

let lucky = 23;  //implicit
lucky = 23; 

//let lucy; //inferred any type
let lucy: number = 23; //explicit


//create own type
type Person = string;
let font: Person; 


//enforce shape of an object with interface
interface Person2 {
    first: string;
    last: string;
    [key: string]: any;
}

const p: Person2 = {
    first: "John",
    last: "Doe"
};

const p2: Person2 = {
    first: "Usain",
    last: "Bolt",
    fast: true
};

//functions
function add(a: number, b: number): number {
    return a + b;
}

function pow(x:number,y:number): number {  //number at the end is return type, number with x and y is parameter type
    return Math.pow(x,y);
}


//arays
const arr: number[] = [1,2,3,4,5]; //number array

//generics
class observable<T> {
    constructor(public value: T) {}
}

let x: observable<number> = new observable(23);
let y: observable<Person2>;    
