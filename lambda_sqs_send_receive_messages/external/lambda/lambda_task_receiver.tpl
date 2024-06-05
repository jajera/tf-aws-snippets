import { DynamoDB } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocument } from "@aws-sdk/lib-dynamodb";

const dynamo = DynamoDBDocument.from(new DynamoDB());

export const handler = async (event) => {
  for (const { messageId, body } of event.Records) {
    console.log("SQS message %s: %j", messageId, body);
    const task = JSON.parse(body);
    await dynamo.put({ Item: task, TableName: "${table_name}" });
    console.log("Task created: ", task);
  }
  return `Successfully processed $${event.Records.length} messages.`;
};
