# Pin npm packages by running ./bin/importmap

pin 'application'
pin '@hotwired/turbo-rails', to: 'turbo.min.js'
pin '@hotwired/stimulus', to: 'stimulus.min.js'
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js'
pin '@rails/activestorage', to: 'activestorage.esm.js'
pin 'sortablejs', to: 'https://ga.jspm.io/npm:sortablejs@1.15.6/modular/sortable.esm.js'
pin '@vektis-io/tracker', to: '@vektis-io--tracker.js' # @1.4.1
# `vektis` and controllers/vektis{,_view}_controller come from the vektis-rails gem's own importmap.
pin_all_from 'app/javascript/controllers', under: 'controllers'
pin_all_from 'app/javascript/lib', under: 'lib'
