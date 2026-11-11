I created a Powershell script to export my Polar data occasionally and save it as JSON dumps on my disk for AI to do me a weekly workout schedule and tracking of my progress.
Feel free to use it yourself if you find it useful.

API documentation  https://www.polar.com/accesslink-api/#polar-accesslink-api
Instructions on usage below. Some parts of it might be inaccurate, but should work as it does work on my machine :)

1. Create account on Polar Flow
2. Fill your application information at https://admin.polaraccesslink.com, 
3. Obtain your application ClientId and replace it below in the variables. Write down secret somewhere as well for later use.
4. RedirectUri is mandatory, but you can use any. Remember to match the one you input on your application with the update-token.ps1 script's variable
5. Use your browser to go to: https://auth.polar.com/oauth/authorize?client_id=<your_clientId>&response_type=code&redirect_uri=<callback_uri>
    Example: https://auth.polar.com/oauth/authorize?client_id=12122b0a-a32a-4f7b-a56f-5339b51348e7&response_type=code&redirect_uri=http://localhost:8080/callback
6  Log in with your Polar Flow account on your browser when prompted
7. Browser should point to your callback url with "code=<your_code>", save the code value for update-token.ps1 script run (or set it manually to variable $Code)
8. Run the script update-token.ps1, it asks for Secret (from when you filled the application information) and the code that you got from the browser's URL box
9. Token should be valid from now on until otherwise revoked, so update-token.ps1 shouldn't be needed to run.
10. Run fetch-from-polar.ps1 from now on. Data is retrievable for 28 days
