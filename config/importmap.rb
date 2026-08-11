# Pin npm packages by running ./bin/importmap

pin 'application'
pin '@hotwired/turbo-rails', to: 'turbo.min.js'
pin '@hotwired/stimulus', to: 'stimulus.min.js'
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js'
pin '@rails/activestorage', to: 'activestorage.esm.js'
pin 'sortablejs', to: 'https://ga.jspm.io/npm:sortablejs@1.15.6/modular/sortable.esm.js'
pin '@vektis-io/tracker', to: '@vektis-io--tracker.js' # local build of unpublished 1.3.0+ (VEK-578)
pin 'vektis' # app/javascript/vektis.js — the shared track() wrapper every call site imports (VEK-581)
pin_all_from 'app/javascript/controllers', under: 'controllers'
