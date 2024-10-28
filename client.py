import os
import datetime
import ssl
import paho.mqtt.client as mqtt

now = datetime.datetime.now()
cwd = os.getcwd()

# Define the MQTT broker parameters
BROKER_ADDRESS = "mosquitto"       # Change to your broker's address
BROKER_PORT = 8883
CA_CERT = cwd + "/certs/ca.crt"           # Path to your CA certificate
CLIENT_CERT = cwd + "/certs/client.crt"   # Path to your client certificate
CLIENT_KEY = cwd + "/certs/client.key"    # Path to your client private key

# Validate that the files exists
if not os.path.isfile(CA_CERT):
    raise ValueError(f"CA_CERT file not found: {CA_CERT}")
print(f"CA_CERT: {CA_CERT}")

if not os.path.isfile(CLIENT_CERT):
    raise ValueError(f"CLIENT_CERT file not found: {CLIENT_CERT}")
print(f"CLIENT_CERT: {CLIENT_CERT}")

if not os.path.isfile(CLIENT_KEY):
    raise ValueError(f"CLIENT_KEY file not found: {CLIENT_KEY}")
print(f"CLIENT_KEY: {CLIENT_KEY}")


# Define the MQTT client callback functions
def on_connect(client, userdata, flags, rc):
    print("Connected with result code: " + str(rc))
    client.subscribe("test/topic")  # Subscribe to a topic

def on_message(client, userdata, msg):
    print(f"Received message: {msg.payload.decode()} on topic: {msg.topic}")

# Create an MQTT client instance
client = mqtt.Client("client")

# Set the on_connect and on_message callbacks
client.on_connect = on_connect
client.on_message = on_message

# Create a SSL context
ssl_context = ssl.create_default_context()
ssl_context.keylog_filename = cwd + "/log/sslkeylog_" + now.strftime("%Y-%m-%d_%H-%M-%S") + ".log"
ssl_context.load_cert_chain(CLIENT_CERT, keyfile=CLIENT_KEY)
ssl_context.load_verify_locations(CA_CERT)

client.tls_set_context(ssl_context)

# Connect to the broker
try:
    client.connect(BROKER_ADDRESS, BROKER_PORT)
    print("Connected to broker")
except Exception as e:
    print(f"Error connecting to broker: {e}")

# Subscribe
print("Subscribing to topic test/topic")
client.subscribe("test/topic")

try:
    # Publish a test message to trigger a response
    print("Publishing on topic test/topic")
    client.publish("test/topic", "Hello MQTT with mTLS again!")

    while True:
        client.loop()
    

except KeyboardInterrupt:
    print("Disconnecting...")
finally:
    client.disconnect()
