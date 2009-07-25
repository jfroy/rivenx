import Foundation

class _ObjCNotificationBounder(Foundation.NSObject):

    def initWithOwner_notificationName_(self, owner, notification_name):
        self = super(_ObjCNotificationBounder, self).init()
        if self is None:
            return None

        self.owner = owner
        Foundation.NSNotificationCenter.defaultCenter().addObserver_selector_name_object_(
            self, '_handleNotification:', notification_name, None)

        return self

    def dealloc(self):
        Foundation.NSNotificationCenter.defaultCenter().removeObserver_(self)
        super(_ObjCNotificationBounder, self).dealloc()

    def _handleNotification_(self, notification):
        Foundation.NSNotificationCenter.defaultCenter().removeObserver_(self)
        self.owner._handle_notification(notification)
        del self.owner

class OneShotNotificationHandler(object):

    def __init__(self, notification_name):
        self.callables = []
        self.bouncer = _ObjCNotificationBounder.alloc().initWithOwner_notificationName_(self, notification_name)

    def add_callable(self, c, *args, **kargs):
        self.callables.append((c, args, kargs))

    def _handle_notification(self, notification):
        for c in self.callables:
            c[0](*c[1], **c[2])
        del self.bouncer
