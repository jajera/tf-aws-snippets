package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs/types"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	
	sqstypes "github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

var (
	regionPtr        = flag.String("region", "", "AWS region (required)")
	queueURLPtr      = flag.String("queue-url", "", "SQS queue URL (required)")
	enableCloudWatch = flag.Bool("enable-cloudwatch", false, "Enable CloudWatch logging")
	logGroupName     = flag.String("log-group", "", "CloudWatch log group name required when enable-cloudwatch is set")
)

func main() {
	flag.Parse()

	// Validate required flags
	if *regionPtr == "" || *queueURLPtr == "" {
		flag.PrintDefaults()
		os.Exit(1)
	}

	if *enableCloudWatch && *logGroupName == "" {
		log.Fatal("log-group is required when enable-cloudwatch is set")
	}

	// Load AWS SDK config
	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithRegion(*regionPtr),
	)
	if err != nil {
		log.Fatalf("Unable to load SDK config: %v", err)
	}

	// Create CloudWatchLogs client if CloudWatch logging is enabled
	var cloudWatchClient *cloudwatchlogs.Client
	if *enableCloudWatch {
		cloudWatchClient = cloudwatchlogs.NewFromConfig(cfg)
	}

	// Create SQS client
	sqsClient := sqs.NewFromConfig(cfg)

	// Handle graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		select {
		case sig := <-sigCh:
			fmt.Printf("\nReceived signal: %v\n", sig)
			cancel() // Cancel context to gracefully shutdown
		}
	}()

	// Start message polling
	go pollMessages(ctx, sqsClient, *queueURLPtr, cloudWatchClient, *logGroupName)

	// Wait for shutdown signal
	<-ctx.Done()

	fmt.Println("\nShutting down gracefully...")
}

func pollMessages(ctx context.Context, sqsClient *sqs.Client, queueURL string, cwClient *cloudwatchlogs.Client, logGroupName string) {
	for {
		select {
		case <-ctx.Done():
			return // Exit goroutine if context is canceled
		default:
			// Receive messages from SQS
			result, err := sqsClient.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
				QueueUrl:            &queueURL,
				MaxNumberOfMessages: 10,
				WaitTimeSeconds:     20,
			})
			if err != nil {
				log.Printf("Error receiving messages: %v", err)
				continue
			}

			// Process received messages
			for _, msg := range result.Messages {
				log.Printf("Received message: %v", *msg.Body)
				// Process the message here

				// Delete the message from the queue
				_, err = sqsClient.DeleteMessage(ctx, &sqs.DeleteMessageInput{
						QueueUrl:      &queueURL,
						ReceiptHandle: msg.ReceiptHandle,
				})
				if err != nil {
						log.Printf("Error deleting message: %v", err)
						continue
				}
				log.Printf("Deleted message: %v", *msg.MessageId)
			}

			// Log to CloudWatch if enabled
			if cwClient != nil {
				err := logToCloudWatch(ctx, cwClient, logGroupName, "Received messages", result.Messages)
				if err != nil {
					log.Printf("Error logging to CloudWatch: %v", err)
				}
			}

			// Simulate polling with a delay
			time.Sleep(5 * time.Second)
		}
	}
}

func logToCloudWatch(ctx context.Context, cwClient *cloudwatchlogs.Client, logGroupName string, message string, messages []sqstypes.Message) error {
	if len(messages) == 0 {
		return nil // No messages to log, so exit early
	}

	logEvents := make([]types.InputLogEvent, len(messages))
	for i, msg := range messages {
		logEvents[i] = types.InputLogEvent{
			Message:   aws.String(fmt.Sprintf("%s: %v", message, *msg.Body)),
			Timestamp: aws.Int64(time.Now().UnixNano() / int64(time.Millisecond)),
		}
	}

	// Create or use a log stream
	currentTime := time.Now()
	truncatedTime := currentTime.Truncate(time.Hour)
	logStreamName := fmt.Sprintf("%d", truncatedTime.Unix())

	// Check if the log stream already exists
	exists, err := logStreamExists(ctx, cwClient, logGroupName, logStreamName)
	if err != nil {
		return fmt.Errorf("failed to check if log stream exists: %v", err)
	}

	if !exists {
		_, err = cwClient.CreateLogStream(ctx, &cloudwatchlogs.CreateLogStreamInput{
			LogGroupName:  aws.String(logGroupName),
			LogStreamName: aws.String(logStreamName),
		})
		if err != nil {
			return fmt.Errorf("failed to create log stream: %v", err)
		}
	}

	_, err = cwClient.PutLogEvents(ctx, &cloudwatchlogs.PutLogEventsInput{
		LogEvents:     logEvents,
		LogGroupName:  aws.String(logGroupName),
		LogStreamName: aws.String(logStreamName),
	})
	if err != nil {
		return fmt.Errorf("failed to write log events: %v", err)
	}

	return nil
}

func logStreamExists(ctx context.Context, cwClient *cloudwatchlogs.Client, logGroupName string, logStreamName string) (bool, error) {
	input := &cloudwatchlogs.DescribeLogStreamsInput{
		LogGroupName:        aws.String(logGroupName),
		LogStreamNamePrefix: aws.String(logStreamName),
	}

	resp, err := cwClient.DescribeLogStreams(ctx, input)
	if err != nil {
		return false, err
	}

	for _, logStream := range resp.LogStreams {
		if *logStream.LogStreamName == logStreamName {
			return true, nil
		}
	}

	return false, nil
}
