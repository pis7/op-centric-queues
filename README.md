# Operation-Centric Queues
Implementation of operation-centric queues which support standardized interfaces for each available operation as opposed to generic write and read ports.

## V1
- Only supports push_back and pop_front operations
- Does not include any operation arbitration

## V2
- Rename push/pop to enq/deq
- Support enq_back, enq_front, deq_back, deq_front operations
- Includes early version of operation arbiter
- New scheme for interface control signals using a request and completion line for each operation

## V3
- Add support for upd and del operations using tags allocated during enq operations

## Testing
- Note: to dump multi-dimensional arrays (including unpacked arrays) with VCS, the `+vcs+dumparrays` plusarg option must be used when calling the executable test