# VERSION

**File:** `lib/auto_doc/version.rb`

### Purpose

Defines the gem version constant. Required by the main `auto_doc.rb` entry point.

### Constant

```ruby
module AutoDoc
  VERSION = "0.2.0"
end
```

### Usage

Loaded by the main entry point (`auto_doc.rb`) as the first require:

```ruby
require_relative "auto_doc/version"
```

Consumed by templates (e.g., `AutoDoc::VERSION` rendered in INDEX.md headers).