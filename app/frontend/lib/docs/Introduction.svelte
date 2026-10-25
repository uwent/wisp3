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
  Weather arrives automatically for each pivot's location. You add what only you know: your rain gauge readings, the
  irrigation you apply, and soil moisture readings now and then to keep the model accurate. Together with your own
  observations in the field, WISP helps you make the most of rain and avoid irrigation that simply drains below the
  roots and carries nutrients with it.
</p>
<p>
  WISP was developed by the Departments of Soil Science and Biological Systems Engineering at the University of
  Wisconsin–Madison, and is maintained by the UW–Madison Vegetable Entomology Lab. It is built for Wisconsin and the
  upper Midwest, and is free to use.
</p>
