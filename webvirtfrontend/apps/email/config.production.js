/*
|-------------------------------------------------------------------------------
| Production config                       https://maizzle.com/docs/environments
|-------------------------------------------------------------------------------
|
| This is where you define settings that optimize your emails for production.
| These will be merged on top of the base config.js, so you only need to
| specify the options that are changing.
|
*/

module.exports = {
  locals: {
    confirm_url: '{{ confirm_url }}',
    reset_url: '{{ reset_url }}',
    site_url: '{{ site_url }}',
  },
  build: {
    templates: {
      destination: {
        path: 'build_production',
      },
    },
  },
  inlineCSS: true,
  removeUnusedCSS: true,
  shorthandCSS: true,
  prettify: true,
}
