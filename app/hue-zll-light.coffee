$(document).on 'templateinit', (event) ->

  # helper function to mix in key/value pairs from another object
  extend = (obj, mixin) ->
    obj[key] = value for key, value of mixin
    obj

  class HueZLLDimmableItem extends pimatic.DeviceItem
    constructor: (templData, @device) ->
      super(templData, @device)
      @switchId = "switch-#{templData.deviceId}"
      @sliderBriId = "bri-#{templData.deviceId}"
      stateAttribute = @getAttribute('state')
      dimAttribute = @getAttribute('dimlevel')
      unless stateAttribute?
        throw new Error("A switch device needs a state attribute!")
      unless dimAttribute?
        throw new Error("A dimmer device needs a dimlevel attribute!")

      @switchState = ko.observable(if stateAttribute.value() then 'on' else 'off')
      @sliderBriValue = ko.observable(if dimAttribute.value()? then dimAttribute.value() else 0)
      stateAttribute.value.subscribe(@_onStateChange)
      dimAttribute.value.subscribe( (newDimlevel) =>
        @sliderBriValue(newDimlevel)
        pimatic.try => @sliderBriEle.slider('refresh')
      )

    afterRender: (elements) ->
      super(elements)
      @switchEle = $(elements).find('select')
      @switchEle.flipswitch()
      @sliderBriEle = $(elements).find('#' + @sliderBriId)
      @sliderBriEle.slider(disabled: @getAttribute('state').value() is off)

      state = @getAttribute('state')
      if state.labels?
        capitaliseFirstLetter = (s) -> s.charAt(0).toUpperCase() + s.slice(1)
        @switchEle.find('option[value=on]').text(capitaliseFirstLetter state.labels[0])
        @switchEle.find('option[value=off]').text(capitaliseFirstLetter state.labels[1])
      $(elements).find('.ui-flipswitch').addClass('no-carousel-slide')
      $(elements).find('.ui-slider').addClass('no-carousel-slide')

    onSwitchChange: ->
      if @_restoringState then return
      stateToSet = (@switchState() is 'on')
      value = @getAttribute('state').value()
      if stateToSet is value
        return
      @switchEle.flipswitch('disable')
      deviceAction = (if @switchState() is 'on' then 'turnOn' else 'turnOff')

      doIt = (
        if @device.config.xConfirm then confirm __("""
          Do you really want to turn %s #{@switchState()}?
        """, @device.name())
        else yes
      )

      restoreState = (if @switchState() is 'on' then 'off' else 'on')

      if doIt
        pimatic.loading "switch-on-#{@switchId}", "show", text: __("switching #{@switchState()}")
        @device.rest[deviceAction]({}, global: no)
          .done(ajaxShowToast)
          .fail( =>
            @_restoringState = true
            @switchState(restoreState)
            pimatic.try => @switchEle.flipswitch('refresh')
            @_restoringState = false
          ).always( =>
            pimatic.loading "switch-on-#{@switchId}", "hide"
            pimatic.try => @switchEle.flipswitch('enable')
          ).fail(ajaxAlertFail)
      else
        @_restoringState = true
        @switchState(restoreState)
        pimatic.try => @switchEle.flipswitch('enable')
        pimatic.try => @switchEle.flipswitch('refresh')
        @_restoringState = false

    onSliderStop: ->
      unless parseInt(@sliderBriValue()) == parseInt(@getAttribute('dimlevel').value())
        @sliderBriEle.slider('disable')
        pimatic.loading(
          "dimming-#{@sliderBriId}", "show", text: __("dimming to %s%", @sliderBriValue())
        )
        @device.rest.changeDimlevelTo( {dimlevel: parseInt(@sliderBriValue())}, global: no).done(ajaxShowToast)
        .always( =>
          pimatic.loading "dimming-#{@sliderBriId}", "hide"
          pimatic.try => @sliderBriEle.slider('enable')
        ).fail(ajaxAlertFail)

    _onStateChange: (newState) =>
       @_restoringState = true
       @switchState(if newState then 'on' else 'off')
       pimatic.try => @switchEle.flipswitch('refresh')
       @_restoringState = false
       @sliderBriEle.slider(if newState then 'enable' else 'disable')

  ColorTempMixin =
    _constructCtSlider: (templData) ->
      @sliderCtId = "ct-#{templData.deviceId}"
      ctAttribute = @getAttribute('ct')
      unless ctAttribute?
        throw new Error("A color temperature device needs a ct attribute!")
      @sliderCtValue = ko.observable(if ctAttribute.value()? then ctAttribute.value() else 370)
      ctAttribute.value.subscribe( (newCtlevel) =>
        @sliderCtValue(newCtlevel)
        pimatic.try => @sliderCtEle.slider('refresh')
      )

    _initCtSlider: (elements) ->
      @sliderCtEle = $(elements).find('#' + @sliderCtId)
      @sliderCtEle.slider(disabled: @getAttribute('state').value() is off)
      $(elements).find('.ui-slider').addClass('no-carousel-slide')

    _ctSliderStopped: ->
      unless parseInt(@sliderCtValue()) == parseInt(@getAttribute('ct').value())
        @sliderCtEle.slider('disable')
        pimatic.loading(
          "colortemp-#{@sliderCtId}", "show", text: __("changing color temp to %s", @sliderCtValue())
        )
        @device.rest.changeCtTo( {ct: parseInt(@sliderCtValue())}, global: no).done(ajaxShowToast)
        .always( =>
          pimatic.loading "colortemp-#{@sliderCtId}", "hide"
          pimatic.try => @sliderCtEle.slider('enable')
        ).fail(ajaxAlertFail)

  class HueZLLColorTempItem extends HueZLLDimmableItem
    constructor: (templData, @device) ->
      super(templData, @device)
      @_constructCtSlider(templData)

    afterRender: (elements) ->
      super(elements)
      @_initCtSlider(elements)

    onSliderStop: ->
      super()
      @_ctSliderStopped()

    _onStateChange: (newState) =>
      super(newState)
      @sliderCtEle.slider(if newState then 'enable' else 'disable')

  extend HueZLLColorTempItem.prototype, ColorTempMixin

  class HueZLLColorItem extends HueZLLDimmableItem
    constructor: (templData, @device) ->
      super(templData, @device)
      hueAttribute = @getAttribute('hue')
      satAttribute = @getAttribute('sat')
      if not hueAttribute? or not satAttribute?
        throw new Error("A color device needs hue/sat attributes!")

      @hueValue = ko.observable(if hueAttribute.value()? then hueAttribute.value() else 0)
      @satValue = ko.observable(if satAttribute.value()? then satAttribute.value() else 0)
      hueAttribute.value.subscribe( (newHue) =>
        @hueValue(newHue)
        pimatic.try => @_updateColorPicker()
      )
      satAttribute.value.subscribe( (newSat) =>
        @satValue(newSat)
        pimatic.try => @_updateColorPicker()
      )

    afterRender: (elements) ->
      super(elements)
      @colorPickerEle = $(elements).find('.ui-colorpicker')
      @colorPicker = @colorPickerEle.find('.light-color')
      @colorPicker.spectrum(
        color: @colorFromHueSat()
        preferredFormat: 'hsv'
        showButtons: false
        showInitial: false
        showInput: true
        showPalette: true
        showSelectionPalette: true
        hideAfterPaletteSelect: true
        localStorageKey: "spectrum.pimatic-hue-zll"
        allowEmpty: false
        disabled: @getAttribute('state').value() is off
        move: (color) =>
          @_updateColorPicker()
          @_changeColor(color)
      )
      @_toggleColorPickerDisable(@getAttribute('state').value())

    colorFromHueSat: ->
      hue = @getAttribute('hue').value() / 65535 * 360
      sat = @getAttribute('sat').value() / 254
      # We don't want to set the brightness (dimlevel) from the color picker,
      # and it wouldn't really match anyway. Lock at 75%
      bri = .75
      return { h: hue, s: sat, v: bri }

    _updateColorPicker: =>
      @colorPicker.spectrum("set", @colorFromHueSat())

    _changeColor: (color) ->
      hueVal = parseInt(color.toHsv()['h'] / 360 * 65535)
      satVal = parseInt(color.toHsv()['s'] * 254)

      @device.rest.changeHueTo( {hue: hueVal}, global: no ).done(ajaxShowToast).fail(ajaxAlertFail)
      @device.rest.changeSatTo( {sat: satVal}, global: no ).done(ajaxShowToast).fail(ajaxAlertFail)

    _toggleColorPickerDisable: (newState) =>
      @colorPicker.spectrum(if newState then 'enable' else 'disable')
      @colorPickerEle.toggleClass('ui-state-disabled', newState is off)
      @colorPickerEle.find(".sp-preview").toggleClass('ui-state-disabled', newState is off)

    _onStateChange: (newState) =>
      super(newState)
      @_toggleColorPickerDisable(newState)

  class HueZLLExtendedColorItem extends HueZLLColorItem
    constructor: (templData, @device) ->
      super(templData, @device)
      @_constructCtSlider(templData)

    afterRender: (elements) ->
      super(elements)
      @_initCtSlider(elements)

    onSliderStop: ->
      super()
      @_ctSliderStopped()

    _onStateChange: (newState) =>
      super(newState)
      @sliderCtEle.slider(if newState then 'enable' else 'disable')

  extend HueZLLExtendedColorItem.prototype, ColorTempMixin

  # register the item-classes
  pimatic.templateClasses['huezlldimmable'] = HueZLLDimmableItem
  pimatic.templateClasses['huezllcolortemp'] = HueZLLColorTempItem
  pimatic.templateClasses['huezllcolor'] = HueZLLColorItem
  pimatic.templateClasses['huezllextendedcolor'] = HueZLLExtendedColorItem
