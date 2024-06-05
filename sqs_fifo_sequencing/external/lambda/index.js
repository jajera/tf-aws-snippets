const AWS = require("aws-sdk");
const sqs = new AWS.SQS({ apiVersion: "2012-11-05" });

exports.handler = async (event) => {
  for (const record of event.Records) {
    const body = record.body;
    const messageAttributes = record.messageAttributes;
    const messageGroupId = messageAttributes.MessageGroupId.stringValue;

    // Process your message here
    console.log(
      `Processing message: ${body}, with MessageGroupId: ${messageGroupId}`
    );

    // Business logic to handle the message goes here
    try {
      // Example: parse the body and process order
      const order = JSON.parse(body);
      // Your order processing logic here
    } catch (error) {
      console.error(`Error processing message: ${error.message}`);
      // Optionally, handle the error (e.g., send to a dead-letter queue)
    }
  }

  return {
    statusCode: 200,
    body: JSON.stringify("Messages processed successfully"),
  };
};
