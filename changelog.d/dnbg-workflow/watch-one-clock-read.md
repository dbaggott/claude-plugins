The PR and issue watches read the clock once per poll instead of once per
question, cutting about a dozen `date` process starts from every tick of a
long-running watch. Nothing a watch reports changes.
