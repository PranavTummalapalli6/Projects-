import requests
import pandas as pd

#download the content of the webpage
response = requests.get("https://api.github.com")
#check if the request was successful
print(response.status_code)


message  = ", Hello World!"
print(message.find("Hello")) #returns the index of the first occurrence of "Hello"

my_list = [1, 2, 3, 4, 5]
my_list.remove(2) #removes the first occurrence of the value 2 from the list
print(my_list[2]) #returns the element at index 2 (which is 3

my_dict = {"name": "Alice", "age": 30, "city": "New York"}
my_dict["has_license"] = True 
print(my_dict["has_license"]) #returns the value associated with the key "has_license" (which is True)
print(my_dict.keys()) #returns a view object that displays a list of all the keys in the dictionary 
print(my_dict.values()) #returns a view object that displays a list of all the values in the dictionary
print(my_dict.items()) #returns a view object that displays a list of all the keys and values in the dictionary

my_set = {1, 2, "three", 4, 5}
print("three" in my_set) #returns True if "three" is in the set, otherwise returns False

my_tuple = (1, 2, 3, 4, 5)
print(my_tuple[1]) #returns the element at index 1 (which is 2)