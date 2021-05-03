from flask import Flask, current_app, request
from flask_restful import Api, Resource
from dateutil import parser
import boto3, uuid, datetime, pytz


class Record:
    def __init__(self, parkingLot, ticketId, plate, en_time, ex_time=None):
        self.parkingLot = parkingLot
        self.plate = plate
        self.en_time = en_time
        self.ex_time = ex_time
        self.ticketId = ticketId

    def serialize(self):
        return {"parkingLot": self.parkingLot,
                "ticketId": self.ticketId.hex if not isinstance(self.ticketId, str) else self.ticketId,
                "plate": self.plate,
                "en_time": self.en_time.isoformat() if not isinstance(self.en_time, str) else self.en_time,
                "ex_time": self.ex_time.isoformat() if ((self.ex_time is not None) and (not isinstance(self.ex_time, str))) else self.ex_time}

    def total_time(self):
        if not self.ex_time:
            raise RuntimeError(
                "The car needs to exit the lot before calculating the time")
        return int(((self.ex_time - parser.parse(self.en_time)).seconds)/60)

    def price(self):
        if not self .ex_time:
            raise RuntimeError(
                "The car needs to exit the lot before calculating the price")
        return (int(self.total_time()/15))*2.5


class Enter(Resource):
    def post(self):
        en_time = datetime.datetime.utcnow().isoformat()
        rec = Record(parkingLot=request.args.get("parkingLot"),
                     ticketId=uuid.uuid4(),
                     plate=request.args.get("plate"),
                     en_time=datetime.datetime.fromisoformat(en_time))

        db = boto3.resource("dynamodb")
        t = db.Table(current_app.config["MAIN_TABLE"])
        t.put_item(Item=rec.serialize())
        return {"ticketId": rec.ticketId.hex}, 200, ({"Content-Type": "application/json"})


class Exit(Resource):
    def post(self):
        ticketId = request.args.get("ticketId")
        db = boto3.resource("dynamodb")
        t = db.Table(current_app.config["MAIN_TABLE"])

        response = t.get_item(Key={"ticketId": ticketId})

        if not response.get("Item"):
            return {"msg": "not found"}, 400

        data = response.get("Item")

        rec = Record(parkingLot=data.get("parkingLot"),
                     ticketId=data.get("ticketId"),
                     plate=data.get("plate"),
                     en_time=data.get("en_time"))

        ex_time = datetime.datetime.utcnow().isoformat()
        ex_time = datetime.datetime.fromisoformat(ex_time)
        rec.ex_time = ex_time
        t.put_item(Item=rec.serialize())

        return ({"plate": rec.plate,
                 "parkingLot": rec.parkingLot,
                 "total_parked_time": rec.total_time(),
                 "charge": rec.price()}, 200,
                ({"Content-Type": "application/json"}))


def run():
    web = Flask(__name__)
    api = Api()
    api.add_resource(Enter, "/entry")
    api.add_resource(Exit, "/exit")
    api.init_app(web)
    web.config["MAIN_TABLE"] = "Data"
    db = boto3.client("dynamodb")
    with web.app_context():
        db.create_table(TableName=current_app.config["MAIN_TABLE"],
                        KeySchema=[
                            {"AttributeName": "ticketId", "KeyType": "HASH"}],
                        AttributeDefinitions=[
                            {"AttributeName": "ticketId", "AttributeType": "S"}],
                        ProvisionedThroughput={"ReadCapacityUnits": 1, "WriteCapacityUnits": 1})
    return web


if __name__ == '__main__':
    web = run()
    web.run(host='0.0.0.0')
