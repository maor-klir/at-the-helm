#helm #kubernetes #resources

# CPU and memory requests and limits

A chart's `resources` value becomes the container's requests and limits, and those decide where a Pod is scheduled, how much CPU it gets, when it's killed, and in which order it's evicted.
The `helm create` scaffold leaves them empty on purpose: *"We usually recommend not to specify default resources and to leave this as a conscious choice for the user."*

This note covers what requests and limits do in Kubernetes, independent of any chart.

## What each setting does

The resource management documentation describes how the container runtime applies them through cgroups:

| Setting | Effect |
|---|---|
| CPU request | used for scheduling, and *"The CPU request typically defines a weighting."* when containers compete for CPU |
| CPU limit | *"The CPU limit defines a hard ceiling on how much CPU time the container can use."* |
| Memory request | *"The memory request is mainly used during (Kubernetes) Pod scheduling."* |
| Memory limit | exceeding it triggers the kernel's out-of-memory handling, which stops a process in the container |

**Requests reserve capacity, whatever the usage:** *"The scheduler ensures that, for each resource type, the sum of the resource requests of the scheduled containers is less than the capacity of the node."*

A container may still use more than it requested: *"If the node where a Pod is running has enough of a resource available, it's possible (and allowed) for a container to use more resource than its `request` for that resource specifies."*

## CPU limits throttle

The kernel enforces a CPU limit in every time slice: *"During each scheduling interval (time slice), the Linux kernel checks to see if this limit is exceeded; if so, the kernel waits before allowing that cgroup to resume execution."*
The check doesn't depend on the rest of the node, so a container can be throttled while most of the node's CPU is idle.

**A test shows the size of the effect:** a CPU-bound Node.js loop, limited to 0.2 CPU on an 8-core machine with a load of about 1.3, ran in a cgroup with `cpu.max` set to `20000 100000`, 20 ms of CPU time per 100 ms period.
The kernel throttled it in 35 of 35 periods, for 2.7 of its 3 seconds, and it completed about a tenth of the iterations it completed without the limit.

**Throttling looks like slowness, not like a failure:** *"container runtimes don't terminate Pods or containers for excessive CPU usage."*
The container's cgroup counts it in `cpu.stat`, as `nr_throttled` and `throttled_usec`, which is worth checking before adding replicas or nodes for a slow workload.

## Memory limits kill

Memory can't be slowed down the way CPU can: *"If the container tries to allocate more memory than this limit, the Linux kernel out-of-memory subsystem activates and, typically, intervenes by stopping one of the processes in the container that tried to allocate memory."*
When that process is PID 1, the container stops, and Kubernetes restarts it if its restart policy allows.

**Usage above the request is what the kubelet evicts first:** under node pressure, *"The kubelet uses the following parameters to determine the pod eviction order:"* whether the usage exceeds the requests, the Pod's priority, and the usage relative to the requests.
A container that stays within its memory request is among the last candidates.

## Quality of service classes

Requests and limits together put each Pod in a class:

| Class | Criteria | Under node pressure |
|---|---|---|
| `Guaranteed` | every container has CPU and memory requests and limits, with each limit equal to its request | *"least likely to face eviction"* |
| `Burstable` | not `Guaranteed`, and at least one container has a CPU or memory request or limit | evicted *"only after all `BestEffort` Pods are evicted"* |
| `BestEffort` | no container has any CPU or memory request or limit | *"The kubelet prefers to evict `BestEffort` Pods if the node comes under resource pressure."* |

`Guaranteed` also matters for CPU pinning: those Pods *"can also make use of exclusive CPUs using the `static` CPU management policy."*

## Two common rules of thumb

**Memory request equal to the limit:** the container's usage can't exceed its request, so it's never in the first eviction group, and the node never promises more memory than it has.
The cost is the burst headroom that the memory task page lists as the reason for a higher limit: *"The Pod can have bursts of activity where it makes use of memory that happens to be available."*

**No CPU limit:** the request alone already protects the container when CPU is scarce, because *"workloads with larger CPU requests are allocated more CPU time than workloads with small requests"*, and idle CPU is used instead of throttled.
The cost is the upper bound, which the CPU task page states: without a limit, *"The Container could use all of the CPU resources available on the Node where it is running."*

**When a CPU limit is still required:** a `Guaranteed` Pod needs one equal to its request, and a namespace with a quota may reject Pods without one: *"users must specify requests or limits for those values when they define a Pod; otherwise, the quota system may reject pod creation."*
A LimitRange can also add a default limit to every container that doesn't set its own.

Following both rules makes a Pod `Burstable`, which suits most applications; neither rule fits every cluster.

## In a chart

A chart passes its `resources` value to the container unchanged, so these trade-offs belong in `values.yaml`.
The `config-store` chart requests `100m` CPU and `128Mi` of memory, and limits them to `200m` and `256Mi`, which makes its Pod `Burstable` (see **41 - The config-store application**).

Its application runs JavaScript on one thread, so under load the `200m` limit throttles it as in the test above, while its memory, about 38 MiB, stays far below both values.
