import requests

city = "New York"

def get_weather(city):
    # Look up coordinates for the city name using Open-Meteo's geocoding API
    geocode_response = requests.get(
        "https://geocoding-api.open-meteo.com/v1/search",
        params={"name": city, "count": 1}
    )
    # get the JSON data from the response
    geocode_data = geocode_response.json()

    # Take the first (best) match and pull out its latitude/longitude
    location = geocode_data["results"][0]
    latitude = location["latitude"]
    longitude = location["longitude"]

    # Use the coordinates to request the current weather
    weather_response = requests.get(
        "https://api.open-meteo.com/v1/forecast",
        params={"latitude": latitude, "longitude": longitude, "current_weather": True}
    )
    # get the JSON data from the response
    weather_data = weather_response.json()

    temperature = weather_data["current_weather"]["temperature"]

    return temperature

print(f"The current temperature in {city} is {get_weather(city)}°C.") #returns the current temperature in degrees Celsius for New York City