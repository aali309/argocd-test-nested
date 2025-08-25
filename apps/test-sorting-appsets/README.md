# Test ApplicationSets for Sorting Functionality

This folder contains ApplicationSets created to test the sorting functionality in the ApplicationSetList component.

## ApplicationSets Overview

### Generated Apps Column Testing (1 generator each, different app counts)

| ApplicationSet | Generated Apps | Purpose |
|----------------|----------------|---------|
| `test-sorting-single-generator` | 1 | Tests single application generation |
| `test-sorting-double` | 2 | Tests two applications generation |
| `test-sorting-multiple` | 3 | Tests three applications generation |
| `test-sorting-quad` | 4 | Tests four applications generation |
| `test-sorting-appset` | 3 | Tests three applications generation |

### Generators Column Testing (different generator counts)

| ApplicationSet | Generators | Purpose |
|----------------|------------|---------|
| `test-sorting-single-generator` | 1 | Tests single generator |
| `test-sorting-two-generators` | 2 | Tests two generators (list + git) |
| `test-sorting-three-generators` | 3 | Tests three generators (list + git + clusterDecisionResource) |
| `test-sorting-multi-generator` | 3 | Tests three generators (list + git + clusterDecisionResource) |

## Expected Sorting Results

### Generated Apps Column
- **Ascending**: 1, 2, 3, 3, 3, 3, 4, 6
- **Descending**: 6, 4, 3, 3, 3, 3, 2, 1

### Generators Column
- **Ascending**: 1, 1, 1, 1, 1, 2, 3, 3
- **Descending**: 3, 3, 2, 1, 1, 1, 1, 1

## Usage

To apply all ApplicationSets:
```bash
kubectl apply -f test-sorting-appsets/
```

To apply individual ApplicationSets:
```bash
kubectl apply -f test-sorting-appsets/test-sorting-single-generator-appset.yaml
```

## Testing Sorting

1. Navigate to the ApplicationSets list in OpenShift Console
2. Click on "Generated Apps" column header to test sorting by application count
3. Click on "Generators" column header to test sorting by generator count
4. Verify ascending/descending order works correctly

## Notes

- All ApplicationSets use the `openshift-gitops` namespace
- All use the same Git repository: `https://github.com/aali309/argocd-test-nested`
- All have automated sync enabled with prune and self-heal
- All include `CreateNamespace=true` sync option
