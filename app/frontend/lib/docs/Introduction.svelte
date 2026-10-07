<script lang="ts">
  import Term from '@/lib/components/Term.svelte'

  // What WISP is, for the landing page and the top of the About page (PLAN.md Phase 6.5)
</script>

<p>
  WISP, the Wisconsin Irrigation Scheduling Program, helps growers decide when to irrigate and how much. For each field
  it keeps a daily water balance of the crop's <Term id="root_zone">root zone</Term>: rain and irrigation in, the crop's
  water use and <Term id="deep_drainage">drainage</Term> out. Run forward with the weather forecast, it shows which fields
  will need water in the next few days, and how much would refill them.
</p>
<p>
  Weather comes in automatically for each pivot's location. What you add is what only you know: your rain gauges, the
  irrigation you apply, and soil moisture readings now and then to keep the model honest. Used with your own field
  observations, WISP helps you make the most of rain while avoiding irrigation that only drains below the roots, taking
  nutrients with it.
</p>
<p>
  WISP was developed by the Departments of Soil Science and Biological Systems Engineering at the University of
  Wisconsin–Madison, and is maintained by the UW–Madison Vegetable Entomology Lab. It is built for Wisconsin and the
  upper Midwest, and is free to use.
</p>
