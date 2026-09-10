# Anonymized validation results

The following measurements are from test/validation environments. Object names and infrastructure details are intentionally omitted.

| Case | Table before | Index before | Total before | Table after | Index after | Total after | Reclaimed | Duration |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Small MV | 112 MB | ~0 MB | 112 MB | 0.69 MB | ~0 MB | 0.69 MB | 111.31 MB | 6 s |
| Medium MV A | 148 MB | 33 MB | 181 MB | 25 MB | 12 MB | 37 MB | 144 MB | 4 s |
| Medium MV B | 160 MB | 3 MB | 163 MB | 2 MB | 2 MB | 4 MB | 159 MB | 2 s |
| Large MV | 13,214.63 MB | 915 MB | 14,129.63 MB | 232 MB | 198 MB | 430 MB | 13,699.63 MB | 20 s |
| Scheduled validation | 1,283 MB | 560 MB | 1,843 MB | 230 MB | 192 MB | 422 MB | 1,421 MB | 16 s |

## Example interpretation

For the scheduled validation case:

```text
Allocated before : 1,843 MB
Allocated after  :   422 MB
Reclaimed        : 1,421 MB
Reduction        : ~77.1%
Refresh duration : 16 seconds
```

The pre-refresh logical estimate for the table was approximately 202.15 MB, compared with a 1,283 MB table segment. That produced an allocation ratio of about 6.35x and an estimated table excess of 1,080.85 MB. The post-refresh measurement then provided the real result: 1,421 MB reclaimed across table + indexes.

These results are not a performance guarantee. The reclaim amount and refresh duration depend on MV query complexity, source-table volume, indexes, storage, concurrency and database configuration.
