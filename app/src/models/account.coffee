class @Account extends Model
  do @init
  @has many: 'operations', sortBy: ['time', 'desc'], onDelete: 'destroy'
  @index 'index'

  @fromHDWalletAccount: (hdAccount) ->
    return null unless hdAccount?
    @find(index: hdAccount.index).first()

  createTransaction: (amount, fees, recipientAddress, callback) ->
    transaction = new ledger.wallet.Transaction()
    transaction.init amount, fees, recipientAddress

  ## Balance management

  retrieveBalance: () ->
    ledger.tasks.BalanceTask.get(@get('index')).startIfNeccessary()

  ## Operations

  addRawTransactionAndSave: (rawTransaction, callback = _.noop) ->
    hdAccount = ledger.wallet.HDWallet.instance?.getAccount(@get('index'))
    ledger.wallet.pathsToAddresses hdAccount.getAllPublicAddressesPaths(), (publicAddresses) =>
      ledger.wallet.pathsToAddresses hdAccount.getAllChangeAddressesPaths(), (changeAddresses) =>
        @_addRawTransaction rawTransaction, _.values(publicAddresses), _.values(changeAddresses)
        @save()
        callback()

  _addRawTransaction: (rawTransaction, publicAddresses, changeAddresses) ->
    rawTransaction.outputAddresses = []
    rawTransaction.inputAddresses = []
    rawTransaction.outputAddresses = rawTransaction.outputAddresses.concat(output.addresses) for output in rawTransaction.outputs
    rawTransaction.inputAddresses = rawTransaction.inputAddresses.concat(input.addresses) for input in rawTransaction.inputs

    hasAddressesInInput = _.some(rawTransaction.inputAddresses, ((address) -> _.contains(publicAddresses, address) or _.contains(changeAddresses, address)))
    hasAddressesInOutput = _.some(rawTransaction.outputAddresses, ((address) -> _.contains(publicAddresses, address)))

    l hasAddressesInInput, hasAddressesInOutput
    if hasAddressesInInput
      @_addRawSendTransaction rawTransaction, changeAddresses

    if hasAddressesInOutput
      @_addRawReceptionTransaction rawTransaction, publicAddresses.concat(changeAddresses)

  _addRawReceptionTransaction: (rawTransaction, ownAddresses) ->
    value = 0
    for output in rawTransaction.outputs
      if _.select(output.addresses, ((address) -> _.contains(ownAddresses, address))).length > 0
        value += parseInt(output.value) if output.value?

    recipients = (address for address in rawTransaction.outputAddresses when _.contains(ownAddresses, address))
    senders = (address for address in rawTransaction.inputAddresses)

    uid = "reception_#{rawTransaction.hash}_#{@get('index')}"

    operation = Operation.findOrCreate uid: uid

    operation.set 'hash', rawTransaction['hash']
    operation.set 'fees', rawTransaction['fees']
    operation.set 'time', (new Date(rawTransaction['chain_received_at'])).getTime()
    operation.set 'type', 'reception'
    operation.set 'value', value
    operation.set 'confirmations', rawTransaction['confirmations']
    operation.set 'senders', senders
    operation.set 'recipients', recipients

    operation.save()
    @add('operations', operation)

  _addRawSendTransaction: (rawTransaction, changeAddresses) ->
    value = 0
    for output in rawTransaction.outputs
      if _.select(output.addresses, ((address) -> _.contains(changeAddresses, address) is false)).length > 0
        value += parseInt(output.value) if output.value?

    recipients = (address for address in rawTransaction.outputAddresses when _.contains(changeAddresses, address) is false)
    senders = (address for address in rawTransaction.inputAddresses)

    uid = "sending#{rawTransaction.hash}_#{@get('index')}"

    operation = Operation.findOrCreate uid: uid

    operation.set 'hash', rawTransaction['hash']
    operation.set 'fees', rawTransaction['fees']
    operation.set 'time', (new Date(rawTransaction['chain_received_at'])).getTime()
    operation.set 'type', 'sending'
    operation.set 'value', value
    operation.set 'confirmations', rawTransaction['confirmations']
    operation.set 'senders', senders
    operation.set 'recipients', recipients

    operation.save()
    @add('operations', operation)
