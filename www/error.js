class EOSError extends Error { }

exports.EOSError = EOSError;

function rejectAsError (reject) {
    return (err) => {
        reject(new EOSError(err));
    };
}
exports.rejectAsError = rejectAsError;
