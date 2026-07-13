class apiConfig:
    def __init__(self, api_key, api_secret, model = "gpt-3.5-turbo", max_tokens = 1024):
        self.api_key = api_key
        self.api_secret = api_secret
        self.model = model
        self.max_tokens = max_tokens
        self.base_url = "https://api.openai.com/v1/completions"

    def get_api_key(self):
        return self.api_key

    def get_api_secret(self):
        return self.api_secret
#Create different configurations for development and production environments
#using positional for required arguments to specify the API key, secret, model, and max tokens for each environment.
dev_config = apiConfig("sk-dev-key", "sk-dev-secret", max_tokens=50)
#instance of class api config for production environment with the API key "sk-prod-key", API secret "sk-prod-secret", model "gpt-4", and max tokens 1000.
prod_config = apiConfig("sk-prod-key", "sk-prod-secret", model="gpt-4", max_tokens=1000)

print(f"Development API Key: {dev_config.get_api_key()}") #returns the API key for the development configuration (which is "sk-dev-key")
print(f"Production API Key: {prod_config.get_api_key()}") #returns the API key for the production configuration (which is "sk-prod-key")