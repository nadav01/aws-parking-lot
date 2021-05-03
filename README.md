# aws-parking-lot

How to use:

1. Clone the repository and cd to the root folder.
2. Run the deployment script: ./deploy.sh

3. After the script finished running, get the instance ip (from aws console / printed to screen during the process)

4. Run the http methods on port 80, for example:

Enter:

curl -X POST 'http://18.202.230.37:80/entry?plate=786-712-123&parkingLot=412' 

{"ticketId": "3954f897e93d4b72822d85cd91eea9f0"}

Then Exit:

curl -X POST 'http://18.202.230.37:80/exit?ticketId=3954f897e93d4b72822d85cd91eea9f0'

{"plate": "786-712-123", "parkingLot": "412", "total_parked_time": 33, "charge": 5.0}

