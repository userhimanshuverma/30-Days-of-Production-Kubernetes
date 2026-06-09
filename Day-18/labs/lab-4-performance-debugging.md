# 🧪 Lab 4: Latency & Bottleneck Analysis

In this lab, you will act as an SRE investigating production performance anomalies. You will inject latency and failures into our mock microservice application and analyze trace timelines to isolate the root cause.

---

## 🎯 Goal
Identify downstream database delays, external payment timeouts, and API errors using trace visualizations.

---

## 🛠️ Step-by-Step Instructions

### Step 1: Inject Downstream Latency
Our mock frontend service is equipped with endpoint query parameters to simulate typical production bugs:
*   `delay`: Simulates database lock contention or thread blocks downstream.
*   `err`: Simulates payment provider gateway aborts.

Trigger a slow request by running:

```bash
curl "http://localhost:8080/?delay=1500"
```

**Expected Output:**
The curl command should hang and complete in roughly **1.5 seconds**.

---

### Step 2: Search and Analyze the Bottleneck in Jaeger
1.  Navigate to your Jaeger UI ([http://localhost:16686](http://localhost:16686)).
2.  Select Service `frontend` and click **Find Traces**.
3.  Look for the trace that took $\approx 1.5$ seconds. Click on it.
4.  Examine the span visualization.

#### 🕵️‍♂️ Investigation:
*   Observe that the top-level (root) span `HTTP GET /` is 1500ms wide.
*   Directly underneath it, look at the child span: `HTTP POST /orders/create` (service: `order-processor`).
*   Expand `order-processor`. Observe the grandchild span: `db-query: SELECT stock FROM inventory` (service: `order-processor`).
*   Notice that the `db-query` span accounts for the vast majority of the time (1500ms).

**Conclusion**: The latency is **not** caused by network overhead between the frontend and backend. It is isolated to a specific database lookup in the `order-processor` database client.

---

### Step 3: Inject an External Service Failure
Now let's simulate a payment handler crash:

```bash
curl "http://localhost:8080/?err=payment_gateway"
```

**Expected Output:**
The request immediately returns a `500 Internal Server Error`.

---

### Step 4: Trace the Error Path
1.  In the Jaeger search screen, select Service `frontend`, change the **Limit Results** to `Errors Only` in the dropdown (or search for traces with an error tag).
2.  Click **Find Traces**. You will see a trace highlighted with a red exclamation mark. Click on it.
3.  The UI expands the trace showing the error propagate upwards:
    *   `GET /` is marked red.
    *   `POST /orders/create` is marked red.
    *   `POST /payments/charge` is marked red.
4.  Click on the `POST /payments/charge` span. Expand its **Tags** and **Logs**.
5.  Under **Tags**, inspect `error = true` and `http.status_code = 502`.
6.  Under **Logs**, check the event timestamp. You should see a message similar to:
    ```text
    event: "error"
    message: "Stripe connection timed out after 3000ms. DNS Resolution failed."
    ```

**Conclusion**: The failure is located in the payment processing stage, caused by an external network failure communicating with Stripe APIs.

---

## 🏆 Summary Checklist: How to Isolate a Bottleneck

When reviewing any slow trace in production, ask these three questions in order:
1.  **Which span is the longest single block of time?** If it is a leaf node (a child with no children, like a SQL query or external API call), that database or service is the bottleneck.
2.  **Is there a gap between spans?** If Span A starts, executes Child B for 10ms, then there is a 500ms gap of empty space before Child C starts, the parent application thread is blocked by CPU calculations (e.g. crypto, serialization) or thread pooling constraints.
3.  **Are calls execution serial or parallel?** If downstream calls stack like stairs (one starts only when the previous ends), they are serial. If they start at the same timestamp, they are parallel.

*Proceed to [Troubleshooting Runbooks](../troubleshooting/runbooks.md).*
