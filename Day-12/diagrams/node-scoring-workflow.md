# 💯 Node Scoring Workflow

This flow diagram illustrates the scoring phase where nodes that pass filtering are evaluated against multiple priority plugins to find the optimal target.

```mermaid
graph TD
    Start["Nodes passing Filtering (Predicates)"] --> ScorePlugins["Run Active Scoring Plugins (Score: 0-100)"]

    subgraph Plugins ["Priority Plugins"]
        Plugin1["ImageLocality<br/>(Cache Hit = Higher Score)"]
        Plugin2["NodeResourcesFitScoring<br/>(Bin Packing vs Spread)"]
        Plugin3["NodeAffinityPriority<br/>(Preferred Node Affinity matches)"]
        Plugin4["TaintTolerationPriority<br/>(Prefer nodes with matched taints)"]
    end

    ScorePlugins --> Plugin1
    ScorePlugins --> Plugin2
    ScorePlugins --> Plugin3
    ScorePlugins --> Plugin4

    Plugin1 --> WeightCalculation["Apply Configured Weights<br/>(Plugin Score * Weight)"]
    Plugin2 --> WeightCalculation
    Plugin3 --> WeightCalculation
    Plugin4 --> WeightCalculation

    WeightCalculation --> TotalSum["Calculate Total Score Per Node<br/>(Sum of Weighted Scores)"]
    TotalSum --> MaxScoreSelection["Select Node with Highest Score"]
    MaxScoreSelection --> TieBreaker{"Is there a tie?"}

    TieBreaker -- "Yes" --> RandomNode["Select one of the tied nodes at random"]
    TieBreaker -- "No" --> BindNode["Bind Pod to Node"]

    RandomNode --> BindNode
```

### Explanatory Summary
1. **Scoring Plugins:** Each plugin returns a score from `0` to `100` for each candidate node.
2. **Weights:** Plugins are configured with a weight (e.g., `ImageLocality` might have a weight of `1`, while `NodeResourcesFit` has a weight of `10`).
3. **Calculation:**
   $$\text{Final Node Score} = \sum (\text{Plugin Score} \times \text{Weight})$$
4. **Tie Breaking:** In case of identical scores, a round-robin or random selection is applied to distribute workloads.
