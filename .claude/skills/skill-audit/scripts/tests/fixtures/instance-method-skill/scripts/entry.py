class Counter:
    def __init__(self):
        self.n = 0

    def bump(self):
        self.n += 1

    def dead_m(self):
        return self.n * 2


c = Counter()
c.bump()
print(c.n)
