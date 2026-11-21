ALTER TABLE WorkflowStatusTransition

ADD COLUMN ActionDisplayName
    VARCHAR(100) NOT NULL
    DEFAULT 'Workflow Action',

ADD COLUMN RequiresReasonFlag
    BOOLEAN NOT NULL
    DEFAULT FALSE,

ADD COLUMN ReasonLabel
    VARCHAR(100) NULL,

ADD COLUMN ConfirmationRequiredFlag
    BOOLEAN NOT NULL
    DEFAULT FALSE,

ADD COLUMN DisplayOrder
    INT NOT NULL
    DEFAULT 0;

UPDATE WorkflowStatusTransition
SET
    ActionDisplayName =
        'Activate Workflow',

    RequiresReasonFlag =
        FALSE,

    ReasonLabel =
        NULL,

    ConfirmationRequiredFlag =
        TRUE,

    DisplayOrder =
        10

WHERE TransitionCode =
      'ACTIVATE_WORKFLOW';

UPDATE WorkflowStatusTransition
SET
    ActionDisplayName =
        'Reject Approval',

    RequiresReasonFlag =
        TRUE,

    ReasonLabel =
        'Rejection Reason',

    ConfirmationRequiredFlag =
        TRUE,

    DisplayOrder =
        20

WHERE TransitionCode =
      'REJECT_WORKFLOW';

UPDATE WorkflowStatusTransition
SET
    ActionDisplayName =
        'Cancel Workflow',

    RequiresReasonFlag =
        TRUE,

    ReasonLabel =
        'Cancellation Reason',

    ConfirmationRequiredFlag =
        TRUE,

    DisplayOrder =
        30

WHERE TransitionCode =
      'CANCEL_WORKFLOW';

UPDATE WorkflowStatusTransition
SET
    ActionDisplayName =
        'Complete Workflow',

    RequiresReasonFlag =
        FALSE,

    ReasonLabel =
        NULL,

    ConfirmationRequiredFlag =
        FALSE,

    DisplayOrder =
        40

WHERE TransitionCode =
      'COMPLETE_WORKFLOW';

UPDATE WorkflowStatusTransition
SET
    ActionDisplayName =
        'Expire Workflow',

    RequiresReasonFlag =
        FALSE,

    ReasonLabel =
        NULL,

    ConfirmationRequiredFlag =
        TRUE,

    DisplayOrder =
        50

WHERE TransitionCode =
      'EXPIRE_WORKFLOW';

