package bakalari

import "encoding/json"

type Subject struct {
	ID string `json:"Id"`
	Abbrev string `json:"Abbrev"`
	Name string `json:"Name"`
}

type Teacher struct {
	ID string `json:"Id"`
	Abbrev string `json:"Abbrev"`
	Name string `json:"Name"`
}

type Hour struct {
	ID int `json:"Id"`
	Caption string `json:"Caption"`
	BeginTime string `json:"BeginTime"`
	EndTime string `json:"EndTime"`
}

type TimetableChange struct {
	ChangeSubject interface{} `json:"ChangeSubject"`
	Day string `json:"Day"`
	Hours string `json:"Hours"`
	ChangeType string `json:"ChangeType"`
	Description string `json:"Description"`
	Time string `json:"Time"`
	TypeAbbrev *string `json:"TypeAbbrev"`
	TypeName *string `json:"TypeName"`
}

type Atom struct {
	HourID int `json:"HourId"`
	GroupIDs []string `json:"GroupIds"`
	SubjectID string `json:"SubjectId"`
	TeacherID string `json:"TeacherId"`
	RoomID string `json:"RoomId"`
	CycleIDs []string `json:"CycleIds"`
	Change *TimetableChange `json:"Change"`
	HomeworkIDs []string `json:"HomeworkIds"`
	Theme string `json:"Theme"`
}

type Day struct {
	DayOfWeek int `json:"DayOfWeek"`
	Date string `json:"Date"`
	DayDescription string `json:"DayDescription"`
	DayType string `json:"DayType"`
	Atoms []Atom `json:"Atoms"`
}

type Class struct { ID string `json:"Id"`; Abbrev string `json:"Abbrev"`; Name string `json:"Name"` }
type Group struct { ClassID string `json:"ClassId"`; ID string `json:"Id"`; Abbrev string `json:"Abbrev"`; Name string `json:"Name"` }
type Room struct { ID string `json:"Id"`; Abbrev string `json:"Abbrev"`; Name string `json:"Name"` }
type Cycle struct { ID string `json:"Id"`; Abbrev string `json:"Abbrev"`; Name string `json:"Name"` }

type TimetableResponse struct {
	Days []Day `json:"Days"`
	Hours []Hour `json:"Hours"`
	Subjects []Subject `json:"Subjects"`
	Teachers []Teacher `json:"Teachers"`
	Classes []Class `json:"Classes"`
	Groups []Group `json:"Groups"`
	Rooms []Room `json:"Rooms"`
	Cycles []Cycle `json:"Cycles"`
}

type Homework struct {
	ID string `json:"ID"`
	Content string `json:"Content"`
	DateEnd string `json:"DateEnd"`
	Subject struct { Abbrev string `json:"Abbrev"` } `json:"Subject"`
	IsDone bool `json:"IsDone"`
}
type HomeworksResponse struct { Homeworks []Homework `json:"Homeworks"` }
type Mark struct { MarkText string `json:"MarkText"`; Caption string `json:"Caption"`; Date string `json:"MarkDate"`; Weight int `json:"Weight"`; IsNew bool `json:"IsNew"` }
type SubjectMarks struct { Subject Subject `json:"Subject"`; AverageText string `json:"AverageText"`; Marks []Mark `json:"Marks"` }
type MarksResponse struct { Subjects []SubjectMarks `json:"Subjects"` }
type AbsenceDay struct { Date string `json:"Date"`; Ok int `json:"Ok"`; Missed int `json:"Missed"`; Late int `json:"Late"`; Soon int `json:"Soon"`; Unsolved int `json:"Unsolved"` }
type AbsenceResponse struct { Absences []AbsenceDay `json:"Absences"` }
type UserInfo struct {
	UserUID string `json:"UserUID"`
	FullName string `json:"FullName"`
	Class struct { Name string `json:"Name"`; Abbrev string `json:"Abbrev"`; Teacher NamedPerson `json:"Teacher"`; ClassTeacher NamedPerson `json:"ClassTeacher"` } `json:"Class"`
	ClassTeacherRaw json.RawMessage `json:"ClassTeacher"`
}
type NamedPerson struct { Name string `json:"Name"`; FullName string `json:"FullName"` }
func (p NamedPerson) DisplayName() string { if p.Name != "" { return p.Name }; return p.FullName }