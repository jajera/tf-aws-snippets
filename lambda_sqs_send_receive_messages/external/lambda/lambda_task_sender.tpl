import { SQS } from "@aws-sdk/client-sqs";

const sqs = new SQS({ apiVersion: "2012-11-05" });
const queueUrl = "${queue_url}";

export const handler = async (event, context) => {
  const task = {
    id: Date.now().toString(),
    description: event.description,
    targetDate: event.targetDate,
    isCompleted: false,
  };

  const result = await sqs.sendMessage({
    MessageBody: JSON.stringify(task),
    QueueUrl: queueUrl,
  });

  console.log(
    `Message sent to the SQS queue with MessageId: $${result.MessageId}`
  );

  return task;
};
