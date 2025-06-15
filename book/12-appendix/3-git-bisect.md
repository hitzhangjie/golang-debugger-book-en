## Appendix: Using git bisect to locate the commit that introduced a bug

`git bisect` is a very useful tool for quickly locating the specific commit that caused a particular error or feature change in a large codebase. It uses a binary search algorithm to gradually narrow down the range of commits that might contain the issue, helping developers find the commit that introduced the bug more quickly.

Here's an example of using `git bisect` to search for the commit that introduced a bug. This example assumes you know that a specific version is working fine (e.g., tag v1.0), while a later version has issues (e.g., the latest master branch):

### Step 1: Start bisect

First, you need to start the bisect search from a known bad state:

```bash
git bisect start
```

### Step 2: Specify a good commit

Specify a version that you're certain has no issues (this can be a tag, branch, or specific commit hash):

```bash
git bisect good v1.0   # Assuming v1.0 is a good state with no bugs.
```

### Step 3: Specify a bad commit

Then specify a version that you're certain has issues (this can also be a tag, branch, or specific commit hash):

```bash
git bisect bad master   # Assuming master is the latest development branch and contains the known bug.
```

### Step 4: Compile and test

Git will automatically switch to a middle point between the two specified commits (chosen through binary search). You need to compile and test at this version to confirm whether the current code has issues:

```bash
make      # Assuming your build command is make.
./test_program    # Run a custom script to check if the bug exists.
```

### Step 5: Provide feedback to git bisect

After performing the compilation and testing, you must tell `git bisect` whether the current commit contains the issue:

- If the current version is good, run:

```bash
git bisect good
```

- If the current version is bad, run:

```bash
git bisect bad
```

### Step 6: Repeat until finding the commit that introduced the bug

Repeat the above steps until `git` finds the specific commit that introduced the bug. When bisect ends, it will print the commit information that was "first marked as bad".

```bash
# It will eventually show something like this:
```

bisect run failed:
c94218e7b5d390a6c6eb7f3f7aaf5aa92e0bddd2 is the first bad commit
commit c94218e7b5d390a6c6eb7f3f7aaf5aa92e0bddd2
Author: Your Name <your.email@example.com>
Date:   Date of commit

    Commit message goes here

:100644 100644 8d9bdc2... a91d6ae... M      filename

```

In this example, `c94218e7b5d390a6c6eb7f3f7aaf5aa92e0bddd2` is the commit that introduced the bug.

### Step 7: Complete bisect
After finding the commit that caused the issue, you can end the bisect with the following command:
```bash
git bisect reset
```

This will restore your working directory to the last branch or tag state before starting `git bisect`. At this point, you have completed the process of using `git bisect` to locate the commit that introduced the bug.

Hope this example helps! If you have more questions or need further assistance, feel free to ask.
