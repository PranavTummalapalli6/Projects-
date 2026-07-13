import tensorflow as tf

# MNIST is built into Keras — 70k labeled handwritten digit images (28x28 pixels)
(x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()

# Normalize pixel values from 0-255 to 0-1 so the network trains faster
x_train = tf.cast(x_train / 255.0, tf.float32)
x_test  = tf.cast(x_test  / 255.0, tf.float32)

model = tf.keras.Sequential([
    # Flatten the 28x28 image into a 784-element vector
    tf.keras.layers.Flatten(input_shape=(28, 28)),
    # Hidden layer: 128 neurons, ReLU activation
    tf.keras.layers.Dense(128, activation="relu"),
    # Dropout randomly disables 20% of neurons each step to prevent overfitting
    tf.keras.layers.Dropout(0.2),
    # Output layer: 10 neurons (one per digit 0-9), softmax gives probabilities
    tf.keras.layers.Dense(10, activation="softmax"),
])

model.summary()

# Gradient descent: Adam adjusts the learning rate per-parameter automatically
optimizer = tf.keras.optimizers.Adam(learning_rate=0.001)
loss_fn   = tf.keras.losses.SparseCategoricalCrossentropy()

# Build batches manually so we control each training step
dataset    = tf.data.Dataset.from_tensor_slices((x_train, y_train)).shuffle(60000).batch(32)
val_dataset = tf.data.Dataset.from_tensor_slices((x_test, y_test)).batch(32)

EPOCHS = 5

for epoch in range(EPOCHS):
    total_loss   = 0.0
    total_correct = 0
    num_batches  = 0

    for x_batch, y_batch in dataset:
        # --- Forward pass + Backpropagation ---
        # GradientTape records every operation inside the block so it can
        # differentiate the loss with respect to each trainable weight
        with tf.GradientTape() as tape:
            predictions = model(x_batch, training=True)   # forward pass
            loss        = loss_fn(y_batch, predictions)   # compute loss

        # Backprop: compute dLoss/dWeight for every trainable parameter
        gradients = tape.gradient(loss, model.trainable_variables)

        # Gradient descent step: nudge each weight opposite to its gradient
        optimizer.apply_gradients(zip(gradients, model.trainable_variables))

        total_loss    += loss.numpy()
        total_correct += tf.reduce_sum(
            tf.cast(tf.argmax(predictions, axis=1) == tf.cast(y_batch, tf.int64), tf.int32)
        ).numpy()
        num_batches += 1

    train_acc = total_correct / len(y_train)

    # Validation pass (no gradient tape needed — inference only)
    val_correct = 0
    for x_batch, y_batch in val_dataset:
        preds = model(x_batch, training=False)
        val_correct += tf.reduce_sum(
            tf.cast(tf.argmax(preds, axis=1) == tf.cast(y_batch, tf.int64), tf.int32)
        ).numpy()
    val_acc = val_correct / len(y_test)

    avg_loss = total_loss / num_batches
    print(f"Epoch {epoch + 1}/{EPOCHS}  loss: {avg_loss:.4f}  train_acc: {train_acc:.2%}  val_acc: {val_acc:.2%}")

# Final evaluation
correct = 0
for x_batch, y_batch in val_dataset:
    preds = model(x_batch, training=False)
    correct += tf.reduce_sum(
        tf.cast(tf.argmax(preds, axis=1) == tf.cast(y_batch, tf.int64), tf.int32)
    ).numpy()

print(f"\nTest accuracy: {correct / len(y_test):.2%}")
