#parent class general animal 
class Animal:
        def __init__(self, name):
            self.name = name
        def speak(self):
            return f"{self.name} makes a sound."
        def move(self):
            return f"{self.name} moves around."

#child class dog that inherits from animal
class Dog(Animal):
        def bark(self):
            return f"{self.name} says woof."
        
#create a dog object
dog = Dog("Buddy")

#call methods from the parent class and child class
print(dog.speak())  # Output: Buddy makes a sound.
print(dog.move())   # Output: Buddy moves around.
print(dog.bark())   # Output: Buddy says woof.