import { SQS } from '@aws-sdk/client-sqs';

const sqs = new SQS({ apiVersion: "2012-11-05" });
const queueUrl = "${queue_url}";
const messageGroupId = "${message_group_id}";

export const handler = async (event) => {
    const messageBody = event.messageBody ? String(event.messageBody) : "This is a test message";
    const messageGroupId = event.messageGroupId ? String(event.messageGroupId) : "defaultGroup";

    const params = {
        MessageBody: messageBody,
        QueueUrl: queueUrl,
        MessageGroupId: messageGroupId,
    };

    try {
        const result = await sqs.sendMessage(params);
        console.log(`Message sent to SQS with MessageId: $${result.MessageId}`);
        return {
            statusCode: 200,
            body: JSON.stringify("Message sent successfully"),
        };
    } catch (error) {
        console.error("Error sending message to SQS:", error);
        return {
            statusCode: 500,
            body: JSON.stringify("Failed to send message"),
        };
    }
};
