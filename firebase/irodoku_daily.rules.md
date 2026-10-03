# RTDB rules fragment for Daily leaderboards

Add this alongside existing `rooms` / `irodoku_progress` rules on
`word-multiplayer` (do not replace the whole ruleset).

```
{
  "rules": {
    "irodoku_daily": {
      "$day": {
        ".read": "auth != null",
        "classic": {
          "$uid": {
            ".write": "auth != null && auth.uid == $uid",
            ".validate": "newData.hasChildren(['name', 'ms', 'at']) && newData.child('ms').isNumber() && newData.child('ms').val() >= 5000 && newData.child('ms').val() <= 86400000 && newData.child('name').isString() && newData.child('name').val().length >= 2 && newData.child('name').val().length <= 10 && newData.child('at').isNumber()"
          }
        },
        "pocket": {
          "$uid": {
            ".write": "auth != null && auth.uid == $uid",
            ".validate": "newData.hasChildren(['name', 'ms', 'at']) && newData.child('ms').isNumber() && newData.child('ms').val() >= 5000 && newData.child('ms').val() <= 86400000 && newData.child('name').isString() && newData.child('name').val().length >= 2 && newData.child('name').val().length <= 10 && newData.child('at').isNumber()"
          }
        }
      }
    }
  }
}
```

Index each day branch on `ms` in Firebase Console if you later switch the client
to `orderByChild('ms').limitToFirst(50)` instead of downloading the day node.
