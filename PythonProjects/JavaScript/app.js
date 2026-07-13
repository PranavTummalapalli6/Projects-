function giveMeClosure(){ // closure
    let a = 23;
    return function(){
        a++;
        return a;
    }
}

//promise
function giveMePromise(){
    return new Promise((resolve, reject) => {
        setTimeout(() => {
            resolve("Hello, World!");
        }, 1000);
    });
}

//garbage collection
function giveMeGarbageCollection(){
    let a = {name: "John"};
    a = null; //garbage collection
}   

//arrays
function giveMeArrays(){
    let arr = [1, 2, 3];
    return arr;
}   

//dict
function giveMeDict(){
    let dict = {name: "John", age: 23};
    return dict;
}   


//set
function giveMeSet(){
    let set = new Set();
    set.add(1);
    set.add(2);
    set.add(3);
    return set;
}           

//prototype chain
function giveMePrototypeChain(){
    function Person(name){
        this.name = name; //this keyword refers to the object that is calling the function
    }
    Person.prototype.sayHello = function(){
        return "Hello, " + this.name;
    }
    let john = new Person("John");
    return john.sayHello(); //Hello, John
}   

//arrow function
const giveMeArrowFunction = () => {
    return "Hello, World!";
}

//bind method
const giveMeBindMethod = () => {
    function Person(name){
        this.name = name;
    }
    Person.prototype.sayHello = function(){
        return "Hello, " + this.name;
    }
    let john = new Person("John");
    let sayHello = john.sayHello.bind(john); //bind method binds the function to the object
    return sayHello(); //Hello, John
}

//async await
async function giveMeAsyncAwait(){
    const result = await giveMePromise();
    return result;  
}

//object
function giveMeObject(){
    let obj = {name: "John", age: 23};
    return obj;
}

//then catch
function giveMeThenCatch(){
    return new Promise((resolve, reject) => {
        setTimeout(() => {
            resolve("Hello, World!");
        }, 1000);
    }).then((message) => {
        return message;
    }).catch((error) => {
        return error;
    });
}



//console log
console.log(giveMeClosure()()); //24
console.log(giveMePromise()); //Promise { <pending> }
console.log(giveMeGarbageCollection()); //undefined
console.log(giveMeArrays()); //[1, 2, 3]
console.log(giveMeDict()); //{name: "John", age: 23}
console.log(giveMeSet()); //Set {1, 2, 3}
console.log(giveMePrototypeChain()); //Hello, John
console.log(giveMeArrowFunction()); //Hello, World!
console.log(giveMeBindMethod()); //Hello, John
console.log(giveMeAsyncAwait()); //Promise { <pending> }
console.log(giveMeObject()); //{name: "John", age: 23}
console.log(giveMeThenCatch()); //Promise { <pending> }