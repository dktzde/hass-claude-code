Templates are short snippets of code you can use wherever Home Assistant needs to figure something out for you. Instead of typing a fixed message or value, you write a small instruction that reads your data and produces the right result.

For example, instead of a notification that always says "Someone is home", a template can say "Frenck is home" or "Nobody is home, they're at the gym" depending on what's actually happening.

## Quick example

{% example %}
action: |
  action: notify.send_message
  target:
    entity_id: notify.my_device
  data:
    message: >
      {% if is_state('device_tracker.frenck', 'home') %}
        Frenck is home.
      {% else %}
        Frenck is at {{ states('device_tracker.frenck') }}.
      {% endif %}
output: "Frenck is at gym."
{% endexample %}

The text between `{%`, `%}` and `{{`, `}}` is the template. When the action runs, Home Assistant replaces it with the right message.

## Learning guide

Start here if you are new to templating in Home Assistant. The pages below walk you through the concepts step by step.

  <h3 class="no_toc">{% icon "mdi:rocket-launch" %} Introduction</h3>What templates are and why you would use them.
  <h3 class="no_toc">{% icon "mdi:map-marker-radius" %} Where to use templates</h3>The places in Home Assistant where templates show up.
  <h3 class="no_toc">{% icon "mdi:code-braces" %} Template syntax</h3>The building blocks of every template, explained in plain language.
  <h3 class="no_toc">{% icon "mdi:sync" %} Loops and conditions</h3>Making decisions and repeating work with <code>if</code>, <code>for</code>, and friends.
  <h3 class="no_toc">{% icon "mdi:file-code-outline" %} Templates in YAML</h3>Quoting, multi-line strings, and other YAML gotchas.
  <h3 class="no_toc">{% icon "mdi:toggle-switch" %} Working with states</h3>Reading states, attributes, and entity information.
  <h3 class="no_toc">{% icon "mdi:swap-horizontal" %} Types and conversion</h3>Understand data types and how to convert between them.
  <h3 class="no_toc">{% icon "mdi:clock-outline" %} Dates and times</h3>Format, compare, and calculate with dates and times.
  <h3 class="no_toc">{% icon "mdi:language-python" %} Python methods</h3>Cheat sheet of Python methods available in templates.
  <h3 class="no_toc">{% icon "mdi:book-open-page-variant" %} Common patterns</h3>Recipes for the things you actually want to do.
  <h3 class="no_toc">{% icon "mdi:bug-outline" %} Debugging templates</h3>Fixing mistakes with the template editor.
  <h3 class="no_toc">{% icon "mdi:alert-circle-outline" %} Error messages</h3>What each error means and how to fix it.
  <h3 class="no_toc">{% icon "mdi:puzzle-outline" %} Custom templates and macros</h3>Share templates across your configuration.

## Tutorials

Two step-by-step walkthroughs that show templating in practice.

  <h3 class="no_toc">{% icon "mdi:battery-alert" %} Notify me about low batteries</h3>Build a daily notification that lists devices with low batteries.
  <h3 class="no_toc">{% icon "mdi:thermometer" %} Average home temperature</h3>Create a template sensor that averages all your temperature sensors.

## Reference

Home Assistant provides hundreds of template functions, filters, and tests for working with your data. Each one has its own page with explanations and examples.

- [Template functions reference](/template-functions/). Browse all functions, filters, and tests by category.
