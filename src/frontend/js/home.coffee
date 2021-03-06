module = angular.module 'ranklist.home', [
  'ui.bootstrap'
  'ui'
  'ngGrid'
  'ranklist.auth'
  'ranklist.resources'
  'ranklist.services'
  'ranklist.injectTransformers'
]

# TODO: Make this into a service?
uHuntURL = 'http://uhunt.felix-halim.net/api'

module.controller 'AddProfileCtrl', ['dialog', '$scope', (dialog, $scope) ->
  $scope.uva = {}
  $scope.submit = ->
    dialog.close(
      name: $scope.name
      uva: $scope.uva
      tags: (_.str.trim(x) for x in $scope.tags.split(','))
    )
]

# From: http://stackoverflow.com/questions/6491463/accessing-nested-javascript-objects-with-string-key
`
Object.byString = function(o, s) {
    s = s.replace(/\[(\w+)\]/g, '.$1'); // convert indexes to properties
    s = s.replace(/^\./, '');           // strip a leading dot
    var a = s.split('.');
    while (a.length) {
        var n = a.shift();
        if (n in o) {
            o = o[n];
        } else {
            return;
        }
    }
    return o;
}
`

module.filter 'join', -> (x) -> _.str.join(',', x...)

# hashes a string into an integer
miniHash = (x, mod) ->
  u = 0
  z = 17
  for c in x
    u += (z*c.charCodeAt(0))
    z *= 17
  ((u*u ^ (u << 1) + 137 * u )*139*u*u + u) % mod


module.controller 'HomeCtrl', ['$log', '$scope', 'CurrentUser', 'Profile', '$dialog', 'Notify', '$http', '$q', 'LoadingNotification', ($log, $scope, CurrentUser, Profile, $dialog, Notify, $http, $q, LoadingNotification) ->
  allProblems = null
  LoadingNotification.loading 'problems'
  $http.get("#{uHuntURL}/p").success((problems) ->
    allProblems = problems
    LoadingNotification.done 'problems'
    loadProfiles()
  ).error((err) ->
    LoadingNotification.done 'problems'
    Notify.error 'Error loading the problem list'
  )
  updateRanks = ->
    if $scope.profiles?
      profiles = _.sortBy($scope.profiles[..], (x) ->
        if x.uva.n_solved?
          -x.uva.n_solved
        else
          10000000
      )
      for profile, idx in profiles
        profile.uva.rank = idx+1
      $scope.filterProfiles()
  loadProfiles = ->
    LoadingNotification.loading 'profiles'
    Profile.query((profiles) ->
      for profile in profiles
        do (profile) ->
          hash = miniHash(profile.name, 0xffffff)
          hue = (hash & 0xff)/0xff
          saturation = 0.70 + ((hash >> 16) & 0xff)/0xff * 0.3
          lightness = ((hash >> 8) & 0xff)/0xff
          profile.color = (new $.color.HSL(hue, saturation, lightness)).hex()
          profile.foreground = (if lightness > 0.5 then '#000' else '#fff')
          if profile.uva.id?
            $http.get("#{uHuntURL}/subs/#{profile.uva.id}").
              success((data) ->
                subs = JSON.parse data.subs
                if subs.length
                  sorted = _.sortBy(subs, (x) -> x[4])
                  profile.uva.latest = new Date((+sorted[sorted.length-1][4])*1000)
                  for sub in subs
                    if sub[2] == 90 # AC
                      pid = sub[1]
                      prob = _.findWhere($scope.problems, id: pid)
                      if prob?
                        unless _.findWhere(prob.solvers, id: profile.id)
                          prob.solvers.push profile
                      else
                        probArr = _.find(allProblems, (x) -> x[0] == pid)
                        prob =
                          id: pid
                          number: probArr[1]
                          title: probArr[2]
                          dacu: probArr[3]
                          solvers: [profile]
                        $scope.problems.push prob
                  $scope.filterProblems()
            )
            $http.get("#{uHuntURL}/ranklist/#{profile.uva.id}/0/0").
              success((data) ->
                data = data[0]
                profile.uva.global_rank = data.rank
                profile.uva.n_solved = data.ac
                profile.uva.n_tries = data.nos
                updateRanks()
              )
      $scope.profiles = profiles
      LoadingNotification.done 'profiles'
    , ->
      LoadingNotification.done 'profiles'
      Notify.error 'Error loading profiles.'
    )

  $scope.tagsTransformer =
    fromModel: (x) ->
      if x?
        ({id: y, text: y} for y in x)
    fromElement: (x) ->
      if x?
        (_.str.trim(y.text) for y in x)

  $scope.tagsSelect2 =
    tags: []
  
  defaultColumns = [
    {
      field: 'name'
      displayName: 'Name'
      cellTemplate: '''
      <div class="ngCellText" ng-class="col.colIndex()" style="background-color: {{ row.entity.color }}; color: {{ row.entity.foreground }}">
        <span>{{row.getProperty(col.field)}}</span>
      </div>
      '''
    }
    {
      field: 'tags'
      displayName: 'Tags'
      cellFilter: 'join'
    }
    {
      field: 'uva.global_rank'
      displayName: 'UVa Global Rank'
    }
    {
      field: 'uva.rank'
      displayName: 'UVa Rank'
    }
    {
      field: 'uva.id'
      displayName: 'UVa ID'
    }
    {
      field: 'uva.username'
      displayName: 'UVa Username'
    }
    {
      field: 'uva.n_solved'
      displayName: 'UVa # Solved'
    }
    {
      field: 'uva.n_tries'
      displayName: 'UVa # Tries'
    }
    {
      field: 'uva.latest'
      displayName: 'Latest Submission'
      cellFilter: 'date'
    }
  ]

  adminColumns = _.map(defaultColumns, (def) ->
    def = _.extend {}, def
    if def.field in ['name', 'uva.username', 'tags']
      def.enableCellEdit = true 
      if def.field == 'tags'
        def.editableCellTemplate = '''
          <input type="hidden" ng-class="'colt' + col.index" ng-model="row.entity.tags" ui-select2="tagsSelect2" inject-transformers="tagsTransformer" multiple/>
          '''
    def
  ).concat [
    {
      field: 'id'
      displayName: 'Save'
      cellTemplate:
        '''
        <div class="ngCellText" ng-class="col.colIndex()"><span ng-cell-text><button class="btn" ng-click="save(row.entity)"><i class="icon-save"></i> Save</button></span></div>
        '''
    }
    {
      field: 'id'
      displayName: 'Delete'
      cellTemplate:
        '''
        <div class="ngCellText" ng-class="col.colIndex()"><span ng-cell-text><button class="btn" ng-click="delete(row.entity)"><i class="icon-remove"></i> Delete</button></span></div>
        '''
    }
  ]

  # the set of columns displayed
  $scope.columnSet = ->
    (if CurrentUser.loggedIn() then adminColumns else defaultColumns)

  # Saves updates to a profile
  $scope.save = (profile) ->
    Profile.update profile, ->
      Notify.success 'Successfully saved updates.'
      loadProfiles()
    , ->
      Notify.error 'Error saving updates.'

  # Deletes a profile
  $scope.delete = (profile) ->
    Profile.delete {id: profile.id}, ->
      Notify.success 'Successfully deleted the profile.'
      loadProfiles()
    , ->
      Notify.error 'Error deleteing the profile.'

  $scope.filteredProfiles = []
  $scope.profileFilters =
    exclude: ''
    include: ''

  $scope.filterProfiles = ->
    fo = $scope.profileFilters
    excluded = (if fo.exclude?.length > 0 then (_.str.trim(x).toLowerCase() for x in fo.exclude.split(',')) else [])
    included = (if fo.include?.length > 0 then (_.str.trim(x).toLowerCase() for x in fo.include.split(',')) else [])
    $log.log included
    $scope.filteredProfiles = _.reject($scope.profiles, (profile) ->
      for tag in excluded
        if _.find(profile.tags, (x) -> x.indexOf(tag) != -1)
          return true
      for tag in included
        unless _.find(profile.tags, (x) -> x.indexOf(tag) != -1)
          return true
      return false
    )

  sortProblems = ->
    sortInfo = $scope.problemGridOptions.sortInfo
    field = sortInfo.fields[0]
    problems = _.sortBy($scope.filteredProblems, (x) -> Object.byString(x, field))
    if sortInfo.directions[0] in ['desc', 'DESC']
      problems.reverse()
    $scope.sortedProblems = problems

  $scope.problems = []
  $scope.filteredProblems = []
  $scope.filterOptions =
    exclude: ''
    include: ''
  $scope.filterProblems = ->
    fo = $scope.filterOptions
    excluded = (if fo.exclude?.length > 0 then (_.str.trim(x).toLowerCase() for x in fo.exclude.split(';')) else [])
    included = (if fo.include?.length > 0 then (_.str.trim(x).toLowerCase() for x in fo.include.split(';')) else [])
    $scope.filteredProblems = _.reject($scope.problems, (prob) ->
      solverNames = (x.name.toLowerCase() for x in prob.solvers)
      for name in excluded
        if _.find(solverNames, (x) -> x.indexOf(name) != -1)
          return true
      for name in included
        unless _.find(solverNames, (x) -> x.indexOf(name) != -1)
          return true
      return false
    )
  $scope.$watch 'problemGridOptions.sortInfo', sortProblems, true
  $scope.$watch 'filteredProblems', sortProblems

  $scope.profileGridOptions = {
    data: 'sortedProfiles'
    columnDefs: 'columnSet()'
    enableCellSelection: true
    enableColumnResize: true
    showFilter: true
    showColumnMenu: true
    sortInfo:
      fields: ['uva.n_solved']
      directions: ['desc']
    virtualizationThreshold: 100
    useExternalSorting: true
  }

  sortProfiles = ->
    sortInfo = $scope.profileGridOptions.sortInfo
    field = sortInfo.fields[0]
    profiles = _.sortBy($scope.filteredProfiles, (x) -> Object.byString(x, field))
    if sortInfo.directions[0] in ['desc', 'DESC']
      profiles.reverse()
    $scope.sortedProfiles = profiles
  $scope.$watch 'profileGridOptions.sortInfo', sortProfiles, true
  $scope.$watch 'filteredProfiles', sortProfiles
  
  $scope.problemGridOptions = {
    data: 'sortedProblems'
    columnDefs: [
      {
        field: 'number',
        displayName: 'Number'
        width: '50px'
      }
      {
        field: 'title'
        displayName: 'Title'
        width: '400px'
      }
      {
        field: 'dacu'
        displayName: 'DACU'
        width: '50px'
      }
      {
        field: 'solvers.length'
        displayName: 'Internal DACU'
        width: '40px'
      }
      {
        field: 'solvers'
        displayName: 'Solvers'
      cellTemplate: '''
      <div class="ngCellText" ng-class="col.colIndex()" style="background-color: {{ row.entity.color }}">
        <div ng-repeat="solver in row.entity.solvers" class="solver-wrapper">
          <div style="background-color: {{ solver.color }}" class="solver-box" ui-jq="tooltip" data-container="body" title="{{solver.name}}"></div>
        </div>
      </div>
      '''
      }
    ]
    enableRowSelection: false
    enableCellSelection: false
    enableColumnResize: true
    showFilter: true
    showColumnMenu: true
    useExternalSorting: true
    sortInfo:
      fields: ['solvers.length']
      directions: ['asc']
  }

  $scope.addProfile = ->
    d = $dialog.dialog(templateUrl: '/templates/add-profile.html', controller: 'AddProfileCtrl')
    d.open().then (params) ->
      def = $q.defer()
      if params.uva.username?
        $http.get("#{uHuntURL}/uname2uid/#{params.uva.username}").success((id) ->
          params.uva.id = id
          def.resolve(params)
        ).error((err) ->
          def.reject("Error getting UVa ID. Perhaps it doesn't exist?")
        )
      else
        def.resolve(params)
      def.promise.then (profile) ->
        Profile.save profile, ->
          Notify.success 'User successfully saved.'
          loadProfiles()
        , ->
          Notify.error 'Failed to save user'
      , (err) ->
        Notify.error err

]
